/** Virtuele aan/uit-status voor discrete openhaarden (geen bus-terugmelding). */

export interface FireplaceVirtualEntry {
  deviceId: string;
  on: boolean;
}

type FireplaceVirtualListener = (entry: FireplaceVirtualEntry) => void;

class FireplaceVirtualService {
  private states = new Map<string, boolean>();
  private listeners = new Set<FireplaceVirtualListener>();

  onChange(fn: FireplaceVirtualListener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  set(deviceId: string, on: boolean): void {
    this.states.set(deviceId, on);
    const entry = { deviceId, on };
    for (const fn of this.listeners) fn(entry);
  }

  get(deviceId: string): boolean | undefined {
    return this.states.get(deviceId);
  }

  getAll(): FireplaceVirtualEntry[] {
    return [...this.states.entries()].map(([deviceId, on]) => ({
      deviceId,
      on
    }));
  }

  clearAll(): void {
    this.states.clear();
  }
}

export const fireplaceVirtual = new FireplaceVirtualService();
