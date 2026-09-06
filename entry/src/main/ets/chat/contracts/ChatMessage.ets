export interface CitationLocation {
  sectionPath: string[];
  start: number;
  end: number;
  anchor?: string;
}

export interface Citation {
  citationId: string;
  label: string;
  title: string;
  originalUrl: string;
  sourceType: 'official_release' | 'official_documentation' | 'official_blog' | 'paper_abstract';
  publishedAt: string | null;
  text: string;
  documentVersionId: string;
  chunkId: string;
  location: CitationLocation;
}

export interface ChatMessage {
  messageId: string;
  chatId: string;
  sequence: number;
  role: 'user' | 'assistant';
  format: 'plain' | 'markdown';
  content: string;
  createdAt: string;
  requestId: string | null;
  taskId: string | null;
  origin: 'interactive' | 'legacy' | 'local';
  draftId: string | null;
  citations: Citation[];
}

export interface MessagePage {
  messages: ChatMessage[];
  olderCursor: string | null;
}

export interface PendingMessage {
  requestId: string;
  text: string;
}
