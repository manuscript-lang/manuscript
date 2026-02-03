// HTTP Capability Adapters
import type { HTTP, HTTPResponse, HTTPOptions } from "./types";

// ============================================
// Fetch-based HTTP Client
// ============================================

export interface FetchHTTPConfig {
  baseURL?: string;
  headers?: Record<string, string>;
  timeout?: number;
}

export class FetchHTTP implements HTTP {
  private baseURL: string;
  private defaultHeaders: Record<string, string>;
  private defaultTimeout: number;
  
  constructor(config: FetchHTTPConfig = {}) {
    this.baseURL = config.baseURL || "";
    this.defaultHeaders = config.headers || {};
    this.defaultTimeout = config.timeout || 30000;
  }
  
  private buildURL(url: string): string {
    if (url.startsWith("http://") || url.startsWith("https://")) {
      return url;
    }
    return this.baseURL + url;
  }
  
  private async makeRequest(
    method: string, 
    url: string, 
    options?: HTTPOptions
  ): Promise<HTTPResponse> {
    const fullURL = this.buildURL(url);
    const headers = { ...this.defaultHeaders, ...options?.headers };
    
    let body: string | undefined;
    if (options?.body) {
      if (typeof options.body === "string") {
        body = options.body;
      } else {
        body = JSON.stringify(options.body);
        headers["Content-Type"] = headers["Content-Type"] || "application/json";
      }
    }
    
    const controller = new AbortController();
    const timeout = options?.timeout || this.defaultTimeout;
    const timeoutId = setTimeout(() => controller.abort(), timeout);
    
    try {
      const response = await fetch(fullURL, {
        method,
        headers,
        body,
        signal: controller.signal,
      });
      
      clearTimeout(timeoutId);
      
      const responseHeaders: Record<string, string> = {};
      response.headers.forEach((value, key) => {
        responseHeaders[key] = value;
      });
      
      return {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders,
        body: await response.text(),
      };
    } catch (error) {
      clearTimeout(timeoutId);
      throw error;
    }
  }
  
  async get(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("GET", url, options);
  }
  
  async post(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("POST", url, options);
  }
  
  async put(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("PUT", url, options);
  }
  
  async patch(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("PATCH", url, options);
  }
  
  async delete(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("DELETE", url, options);
  }
  
  async request(method: string, url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest(method.toUpperCase(), url, options);
  }
  
  async getJSON<T = any>(url: string, options?: HTTPOptions): Promise<T> {
    const response = await this.get(url, options);
    return JSON.parse(response.body);
  }
  
  async postJSON<T = any>(url: string, data: any, options?: HTTPOptions): Promise<T> {
    const response = await this.post(url, { ...options, body: data });
    return JSON.parse(response.body);
  }
}

// ============================================
// Mock HTTP Client for Testing
// ============================================

export interface MockHTTPResponse {
  match: string | RegExp;
  method?: string;
  response: Partial<HTTPResponse>;
}

export interface MockHTTPConfig {
  responses?: MockHTTPResponse[];
}

export class MockHTTP implements HTTP {
  private responses: MockHTTPResponse[];
  private requestHistory: { method: string; url: string; options?: HTTPOptions }[] = [];
  
  constructor(config: MockHTTPConfig = {}) {
    this.responses = config.responses || [];
  }
  
  // Test helpers
  getRequestHistory(): { method: string; url: string; options?: HTTPOptions }[] {
    return this.requestHistory;
  }
  
  clearHistory(): void {
    this.requestHistory = [];
  }
  
  addResponse(
    match: string | RegExp, 
    response: Partial<HTTPResponse>, 
    method?: string
  ): void {
    this.responses.push({ match, response, method });
  }
  
  private findResponse(method: string, url: string): MockHTTPResponse | undefined {
    for (const mock of this.responses) {
      if (mock.method && mock.method.toUpperCase() !== method.toUpperCase()) {
        continue;
      }
      
      if (typeof mock.match === "string") {
        if (url.includes(mock.match)) {
          return mock;
        }
      } else {
        if (mock.match.test(url)) {
          return mock;
        }
      }
    }
    return undefined;
  }
  
  private async makeRequest(
    method: string, 
    url: string, 
    options?: HTTPOptions
  ): Promise<HTTPResponse> {
    this.requestHistory.push({ method, url, options });
    
    const mock = this.findResponse(method, url);
    if (mock) {
      return {
        status: mock.response.status ?? 200,
        statusText: mock.response.statusText ?? "OK",
        headers: mock.response.headers ?? {},
        body: mock.response.body ?? "",
      };
    }
    
    // Default: 404 Not Found
    return {
      status: 404,
      statusText: "Not Found",
      headers: {},
      body: `{"error": "Mock: no response configured for ${method} ${url}"}`,
    };
  }
  
  async get(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("GET", url, options);
  }
  
  async post(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("POST", url, options);
  }
  
  async put(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("PUT", url, options);
  }
  
  async patch(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("PATCH", url, options);
  }
  
  async delete(url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest("DELETE", url, options);
  }
  
  async request(method: string, url: string, options?: HTTPOptions): Promise<HTTPResponse> {
    return this.makeRequest(method.toUpperCase(), url, options);
  }
  
  async getJSON<T = any>(url: string, options?: HTTPOptions): Promise<T> {
    const response = await this.get(url, options);
    return JSON.parse(response.body);
  }
  
  async postJSON<T = any>(url: string, data: any, options?: HTTPOptions): Promise<T> {
    const response = await this.post(url, { ...options, body: data });
    return JSON.parse(response.body);
  }
}
