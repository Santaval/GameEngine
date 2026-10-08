import type { PlayerId } from "./protocol.js";

export interface RoomChange {
  /** New host id if the host changed as a result, else null. */
  hostChanged: PlayerId | null;
}

/** Membership and host election. Host = earliest-joined member still present. */
export class Room<C = unknown> {
  readonly clients = new Map<PlayerId, C>();

  get hostId(): PlayerId | null {
    for (const id of this.clients.keys()) return id;
    return null;
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
