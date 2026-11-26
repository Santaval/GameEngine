import { describe, expect, it, vi } from "vitest";
import { validateMessage } from "../src/protocol.js";
import { Room } from "../src/room.js";
import { useServer, type Connected } from "./helpers.js";

describe("Room host election with ineligible members", () => {
  it("never elects ineligible members and reports host changes", () => {
    const room = new Room<{ bot: boolean }>((c) => !c.bot);
    expect(room.add("b1", { bot: true }).hostChanged).toBeNull();
    expect(room.hostId).toBeNull();
    expect(room.add("h1", { bot: false }).hostChanged).toBe("h1");
    room.add("b2", { bot: true });
    room.add("h2", { bot: false });
    expect(room.humanCount).toBe(2);
    expect(room.remove("h1").hostChanged).toBe("h2");
    expect(room.remove("b1").hostChanged).toBeNull();
    expect(room.hostId).toBe("h2");
  });
});

describe("server bots", () => {
  const env = useServer({ bots: 4, botBrain: "heuristic", botStepMs: 10 });

  /** Tracks who is in the room (and their ships/host changes) from one client's point of view. */
  function watch(c: Connected) {
    const present = new Set<string>(c.welcome.peers);
    const spawned = new Set<string>();
    const hostChanges: string[] = [];
    c.client.ws.on("message", (d) => {
      const m = JSON.parse(d.toString());
      expect(validateMessage(m), JSON.stringify(m)).toBe(true);
      if (m.t === "peer_joined") present.add(m.playerId);
      if (m.t === "peer_left") present.delete(m.playerId);
      if (m.t === "spawn") spawned.add(m.owner);
      if (m.t === "host_changed") hostChanges.push(m.hostId);
    });
    return { present, spawned, hostChanges };
  }

  it("fills up to BOTS, announces bot ships and keeps the human as host", async () => {
    const a = await env.connect();
    const w = watch(a);
    expect(a.welcome.hostId).toBe(a.playerId);
    await vi.waitFor(() => expect(w.present.size).toBe(3)); // 1 human + 3 bots
    await vi.waitFor(() => expect(w.spawned.size).toBe(3));
    expect([...w.spawned].sort()).toEqual([...w.present].sort());
    expect(w.hostChanges).toEqual([]);
  });

  it("drops a bot per extra human, down to none at 4 humans", async () => {
    const a = await env.connect();
    const w = watch(a);
    await vi.waitFor(() => expect(w.present.size).toBe(3));
    const b = await env.connect();
    expect(b.welcome.hostId).toBe(a.playerId);
    await vi.waitFor(() => expect(w.present.size).toBe(3)); // a's view: b + 2 bots
    const c = await env.connect();
    const d = await env.connect();
    await vi.waitFor(() => expect(w.present.size).toBe(3)); // b, c, d and no bots
    expect([b.playerId, c.playerId, d.playerId].every((id) => w.present.has(id))).toBe(true);
    expect(w.hostChanges).toEqual([]);
  });

  it("removes every bot when the last human leaves, and the next human is host", async () => {
    const a = await env.connect();
    const w = watch(a);
    await vi.waitFor(() => expect(w.present.size).toBe(3));
    const bots = [...w.present];
    a.client.ws.close();
    await new Promise((r) => setTimeout(r, 300));
    const b = await env.connect();
    expect(b.welcome.hostId).toBe(b.playerId);
    // the old bots are gone: none of them is a peer of the new human
    await vi.waitFor(() => expect(b.welcome.peers.some((p: string) => bots.includes(p))).toBe(false));
  });
});
