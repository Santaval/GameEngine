#pragma once
#include <atomic>
#include <cstdint>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>

// IXWebSocket se queda fuera del grafo de includes
namespace ix { class WebSocket; }

// Cliente WebSocket no bloqueante. IXWebSocket corre en su propio hilo: ese hilo
// solo toca la cola protegida por mutex y los atomics. Todo lo demas (logs,
// estado, handlers) ocurre en poll(), que se llama desde el hilo principal.
class NetClient {
    public:
        using Handler = std::function<void(const nlohmann::json&)>;

    private:
        std::unique_ptr<ix::WebSocket> ws;

        // Hilo del socket -> hilo principal
        std::mutex queueMutex;
        std::deque<nlohmann::json> inbound;
        std::atomic<bool> connected{false};
        std::atomic<uint64_t> seq{0};

        bool started = false;
        std::string url;
        std::string name;

        // Estado de sesion: solo se modifica desde poll()
        bool welcomed = false;
        // Evita repetir el log en cada intento fallido de reconexion
        bool downLogged = false;
        std::string myPlayerId;
        std::string hostId;
        std::vector<std::string> peers;
        std::map<std::string, std::vector<Handler>> subscribers;

        nlohmann::json stamp(nlohmann::json msg);
        void handleMessage(const nlohmann::json& msg);

    public:
        NetClient();
        ~NetClient();

        void connect(const std::string& url, const std::string& name);
        void disconnect();
        bool send(nlohmann::json msg);
        void poll();
        bool isOnline() const { return connected.load() && welcomed; }
        void subscribe(const std::string& type, Handler handler);

        const std::string& getMyPlayerId() const { return myPlayerId; }
        const std::string& getHostId() const { return hostId; }
        const std::vector<std::string>& getPeers() const { return peers; }
        bool isHost() const { return welcomed && myPlayerId == hostId; }
};
