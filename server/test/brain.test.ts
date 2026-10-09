import { describe, expect, it, vi } from "vitest";
import type { Observation } from "../src/bots/botLogic.js";
import { HeuristicBrain, JevBrain, type DecideFn } from "../src/bots/brain.js";

function obs(over: Partial<Observation> = {}): Observation {
  return {
    self: { hp: 100, score: 0, rank: 2, players: 3, pvp: true, edgeDistance: 5000, shield: 0 },
    enemies: [
      { slot: 0, id: "pA", name: "A", distance: 700, hp: 80, score: 0, isLeader: false, approaching: false },
      { slot: 1, id: "pB", name: "B", distance: 2000, hp: 100, score: 30, isLeader: true, approaching: false },
    ],
    loot: [],
    threat: { incomingBullets: 0, nearestEtaSec: null },
    ...over,
  };
}

const signal = () => new AbortController().signal;

describe("HeuristicBrain", () => {
  const h = new HeuristicBrain();
  it("flees when hurt with an enemy close", () => {
    const o = obs();
    o.self.hp = 20;
    expect(h.decideSync(o).mode).toBe("flee");
  });
  it("collects loot when no threat", () => {
    const o = obs({ enemies: [], loot: [{ distance: 500, quantity: 5 }] });
    expect(h.decideSync(o).mode).toBe("collect");
  });
  it("attacks a weaker enemy in range with pvp", () => {
    expect(h.decideSync(obs())).toMatchObject({ mode: "attack", targetId: "pA" });
  });
  it("hunts the leader when nobody weaker is near", () => {
    const o = obs();
    o.enemies = [o.enemies[1]];
    o.enemies[0].distance = 2500;
    expect(h.decideSync(o)).toMatchObject({ mode: "hunt_leader", targetId: "pB" });
  });
  it("does not attack with pvp off", () => {
    const o = obs();
    o.self.pvp = false;
    expect(h.decideSync(o).mode).toBe("roam");
  });
});

describe("JevBrain", () => {
  it("maps the answers to a decision", async () => {
    const decide = vi.fn<DecideFn>(async () => ({
      answers: {
        mode: { type: "choice", choice: "attack" },
        target: { type: "choice", choice: "e1" },
        aggression: { type: "score", score: 1.5 },
      },
    }));
    const brain = new JevBrain({ model: "m", decide });
    const d = await brain.decide(obs(), signal());
    expect(d).toEqual({ mode: "attack", targetId: "pB", aggression: 0.75 });
    const call = decide.mock.calls[0][0];
    expect(call.model).toBe("m");
    expect(Object.keys(call.questions)).toEqual(["mode", "aggression", "target"]);
    // ids are hidden from the model
    expect(JSON.stringify(call.state)).not.toContain("pA");
  });

  it("falls back to the heuristic on an invalid choice (attack with pvp off)", async () => {
    const o = obs();
    o.self.pvp = false;
    const decide: DecideFn = async () => ({
      answers: { mode: { choice: "attack" }, target: { choice: "none" }, aggression: { score: 0 } },
    });
    const d = await new JevBrain({ model: "m", decide }).decide(o, signal());
    expect(d.mode).toBe("roam");
    expect(d.targetId).toBeNull();
  });

  it("attack without a valid target gets the heuristic/nearest target", async () => {
    const decide: DecideFn = async () => ({
      answers: { mode: { choice: "attack" }, target: { choice: "none" }, aggression: { score: 1 } },
    });
    const d = await new JevBrain({ model: "m", decide }).decide(obs(), signal());
    expect(d).toMatchObject({ mode: "attack", targetId: "pA" });
  });

  it("falls back on errors and on timeout", async () => {
    const boom: DecideFn = async () => {
      throw new Error("boom");
    };
    const hang: DecideFn = () => new Promise(() => {});
    const err = await new JevBrain({ model: "m", decide: boom }).decide(obs(), signal());
    expect(err.mode).toBe("attack");
    const slow = await new JevBrain({ model: "m", decide: hang, timeoutMs: 20 }).decide(obs(), signal());
    expect(slow.mode).toBe("attack");
  });

  it("opens a circuit breaker after 3 failures and recovers after the cool-down", async () => {
    let t = 0;
    const decide = vi.fn<DecideFn>(async () => {
      throw new Error("down");
    });
    const log = vi.fn();
    const brain = new JevBrain({ model: "m", decide, now: () => t, breakerMs: 60_000, log });
    for (let i = 0; i < 3; i++) await brain.decide(obs(), signal());
    expect(decide).toHaveBeenCalledTimes(3);
    expect(brain.breakerOpen).toBe(true);
    expect(log.mock.calls.filter((c) => c[0] === "jev_circuit_open")).toHaveLength(1);
    await brain.decide(obs(), signal());
    expect(decide).toHaveBeenCalledTimes(3); // skipped while open
    t = 60_001;
    await brain.decide(obs(), signal());
    expect(decide).toHaveBeenCalledTimes(4);
  });

  it("skips the call when nothing is near", async () => {
    const decide = vi.fn<DecideFn>();
    const o = obs({ enemies: [], loot: [{ distance: 9000, quantity: 1 }] });
    const d = await new JevBrain({ model: "m", decide }).decide(o, signal());
    expect(d.mode).toBe("roam");
    expect(decide).not.toHaveBeenCalled();
  });
});
