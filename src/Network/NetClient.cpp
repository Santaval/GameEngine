#include "NetClient.hpp"

#include <algorithm>
#include <chrono>
#include <iostream>

#include <ixwebsocket/IXWebSocket.h>

// Debe coincidir con PROTOCOL_VERSION de server/src/protocol.ts
static const int PROTOCOL_VERSION = 1;

using json = nlohmann::json;

NetClient::NetClient() = default;

NetClient::~NetClient() {
    this->disconnect();
}

json NetClient::stamp(json msg) {
    if (!msg.contains("seq")) {
        msg["seq"] = this->seq.fetch_add(1);
    }
    if (!msg.contains("ts")) {
        msg["ts"] = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
    }
    return msg;
}

void NetClient::connect(const std::string& url, const std::string& name) {
    if (this->started) {
        return;
    }
    this->url = url;
    this->name = name;
    this->started = true;
    this->ws = std::make_unique<ix::WebSocket>();
    this->ws->setUrl(url);

    // Este callback corre en el hilo del socket: solo cola y atomics
    this->ws->setOnMessageCallback([this](const ix::WebSocketMessagePtr& m) {
        switch (m->type) {
            case ix::WebSocketMessageType::Open: {
                this->connected = true;
                json hello = {
                    {"t", "hello"},
                    {"name", this->name},
                    {"version", PROTOCOL_VERSION}
                };
                this->ws->sendText(this->stamp(hello).dump());

                std::lock_guard<std::mutex> lock(this->queueMutex);
                this->inbound.push_back({{"t", "_connected"}, {"url", this->url}});
                break;
            }
            case ix::WebSocketMessageType::Message: {
                json msg = json::parse(m->str, nullptr, false);
                if (msg.is_discarded() || !msg.is_object() || !msg.contains("t") || !msg["t"].is_string()) {
                    break;
                }
                std::lock_guard<std::mutex> lock(this->queueMutex);
                this->inbound.push_back(std::move(msg));
                break;
            }
            case ix::WebSocketMessageType::Close: {
                this->connected = false;
                std::lock_guard<std::mutex> lock(this->queueMutex);
                this->inbound.push_back({
                    {"t", "_disconnected"},
                    {"code", m->closeInfo.code},
                    {"reason", m->closeInfo.reason}
                });
                break;
            }
            case ix::WebSocketMessageType::Error: {
                // Con reconexion automatica cada intento fallido genera un Error:
                // solo se avisa si estabamos conectados o es el primer fallo
                this->connected = false;
                std::lock_guard<std::mutex> lock(this->queueMutex);
                this->inbound.push_back({
                    {"t", "_disconnected"},
                    {"code", m->errorInfo.http_status},
                    {"reason", m->errorInfo.reason}
                });
                break;
            }
            default:
                break;
        }
    });

    this->ws->start();
}

void NetClient::disconnect() {
    if (this->ws) {
        // stop() espera al hilo de IXWebSocket
        this->ws->stop();
        this->ws.reset();
    }
    this->connected = false;
}

bool NetClient::send(json msg) {
    if (!this->ws || !this->connected.load()) {
        return false;
    }
    return this->ws->sendText(this->stamp(std::move(msg)).dump()).success;
}

void NetClient::subscribe(const std::string& type, Handler handler) {
    this->subscribers[type].push_back(std::move(handler));
}

void NetClient::poll() {
    // Sin --server no hay nada que hacer
    if (!this->started) {
        return;
    }

    std::deque<json> batch;
    {
        std::lock_guard<std::mutex> lock(this->queueMutex);
        batch.swap(this->inbound);
    }

    for (const auto& msg : batch) {
        this->handleMessage(msg);
    }
}

void NetClient::handleMessage(const json& msg) {
    const std::string t = msg["t"].get<std::string>();

    try {
        if (t == "_connected") {
            this->downLogged = false;
            std::cout << "[Net] connected to " << msg.value("url", "") << std::endl;
        } else if (t == "_disconnected") {
            if (!this->downLogged) {
                std::cout << "[Net] disconnected (code=" << msg.value("code", 0)
                          << ", reason=" << msg.value("reason", "") << ")" << std::endl;
                this->downLogged = true;
            }
            this->welcomed = false;
            this->myPlayerId.clear();
            this->hostId.clear();
            this->peers.clear();
        } else if (t == "welcome") {
            this->myPlayerId = msg.at("playerId").get<std::string>();
            this->hostId = msg.at("hostId").get<std::string>();
            this->peers = msg.at("peers").get<std::vector<std::string>>();
            this->welcomed = true;

            std::cout << "[Net] welcome: playerId=" << this->myPlayerId
                      << " hostId=" << this->hostId << " peers=[";
            for (size_t i = 0; i < this->peers.size(); i++) {
                std::cout << (i ? "," : "") << this->peers[i];
            }
            std::cout << "]" << std::endl;
        } else if (t == "peer_joined") {
            const std::string id = msg.at("playerId").get<std::string>();
            if (std::find(this->peers.begin(), this->peers.end(), id) == this->peers.end()) {
                this->peers.push_back(id);
            }
            std::cout << "[Net] peer_joined: " << id << std::endl;
        } else if (t == "peer_left") {
            const std::string id = msg.at("playerId").get<std::string>();
            this->peers.erase(std::remove(this->peers.begin(), this->peers.end(), id), this->peers.end());
            std::cout << "[Net] peer_left: " << id << std::endl;
        } else if (t == "host_changed") {
            this->hostId = msg.at("hostId").get<std::string>();
            std::cout << "[Net] host_changed: hostId=" << this->hostId << std::endl;
        }
    } catch (const std::exception& e) {
        std::cout << "[Net] bad '" << t << "' message: " << e.what() << std::endl;
    }

    auto it = this->subscribers.find(t);
    if (it == this->subscribers.end()) {
        return;
    }
    // Copia: un handler podria suscribir otro y invalidar la iteracion
    const std::vector<Handler> handlers = it->second;
    for (const auto& handler : handlers) {
        try {
            handler(msg);
        } catch (const std::exception& e) {
            std::cout << "[Net] handler for '" << t << "' failed: " << e.what() << std::endl;
        }
    }
}
