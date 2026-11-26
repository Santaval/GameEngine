import type { PlayerId } from "./protocol.js";

export interface RoomChange {
  /** New host id if the host changed as a result, else null. */
  hostChanged: PlayerId | null;
}

/**
 * Membership and host election. Host = earliest-joined eligible member still
 * present (server bots are not eligible: the host must simulate the map).
 */
export class Room<C = unknown> {
  readonly clients = new Map<PlayerId, C>();

  constructor(private readonly isEligibleHost: (c: C) => boolean = () => true) {}

  get hostId(): PlayerId | null {
    for (const [id, c] of this.clients) if (this.isEligibleHost(c)) return id;
    return null;
  }

  /** Members eligible to be host (humans). */
  get humanCount(): number {
    let n = 0;
    for (const c of this.clients.values()) if (this.isEligibleHost(c)) n++;
    return n;
  }

  has(id: PlayerId): boolean {
    return this.clients.has(id);
  }

  get size(): number {
    return this.clients.size;
  }

  add(id: PlayerId, client: C): RoomChange {
    const before = this.hostId;
    this.clients.set(id, client);
    const after = this.hostId;
    return { hostChanged: after !== before ? after : null };
  }

  remove(id: PlayerId): RoomChange {
    const before = this.hostId;
    this.clients.delete(id);
    const after = this.hostId;
    return { hostChanged: after !== before ? after : null };
  }

  peersOf(id: PlayerId): PlayerId[] {
    return [...this.clients.keys()].filter((k) => k !== id);
  }
}
