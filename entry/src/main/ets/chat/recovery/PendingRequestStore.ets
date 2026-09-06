export interface PendingOperation {
  kind: 'send' | 'retry' | 'stop';
  requestId: string;
  text: string;
  taskId: string;
}

// This journal contains only one unconfirmed write, never authoritative chat facts.
export interface PendingRequestStore {
  read(): PendingOperation | null;
  save(operation: PendingOperation): void;
  clear(): void;
}

export class MemoryPendingRequestStore implements PendingRequestStore {
  private operation: PendingOperation | null = null;

  read(): PendingOperation | null {
    return this.operation;
  }

  save(operation: PendingOperation): void {
    this.operation = operation;
  }

  clear(): void {
    this.operation = null;
  }
}
