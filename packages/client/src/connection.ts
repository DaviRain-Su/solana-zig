/**
 * Connection — RPC client wrapper with injectable transport.
 *
 * Mirrors: RpcClient from src/solana/rpc/client.zig
 * Contract: AC-01 (transport injection), AC-07 (endpoint configurable)
 */

import type {
  Transport,
  RpcResult,
  LatestBlockhash,
  OwnedJson,
} from "./types.js";

// --- Default fetch-based transport ---

function createFetchTransport(): Transport {
  return {
    async postJson(url: string, payload: string): Promise<string> {
      const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: payload,
      });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
      }
      return res.text();
    },
  };
}

// --- Connection class ---

export class Connection {
  readonly endpoint: string;
  private transport: Transport;
  private nextId: number = 1;

  /**
   * Create a Connection with the default fetch transport.
   * AC-07: endpoint is a configurable string.
   */
  constructor(endpoint: string);
  /**
   * Create a Connection with an injected transport.
   * AC-01: supports transport injection for mock / E2E testing.
   */
  constructor(endpoint: string, transport: Transport);
  constructor(endpoint: string, transport?: Transport) {
    this.endpoint = endpoint;
    this.transport = transport ?? createFetchTransport();
  }

  /**
   * AC-01 equivalent: initWithTransport factory (alternative to constructor overload).
   */
  static initWithTransport(
    endpoint: string,
    transport: Transport
  ): Connection {
    return new Connection(endpoint, transport);
  }

  // --- RPC methods ---

  /**
   * AC-02: getLatestBlockhash — returns typed LatestBlockhash with
   * `blockhash` (string) + `last_valid_block_height` (number).
   */
  async getLatestBlockhash(): Promise<RpcResult<LatestBlockhash>> {
    const id = this.nextId++;
    const payload = JSON.stringify({
      jsonrpc: "2.0",
      id,
      method: "getLatestBlockhash",
      params: [{ commitment: "confirmed" }],
    });

    const raw = await this.transport.postJson(this.endpoint, payload);
    const json = JSON.parse(raw);

    if (json.error) {
      return {
        kind: "rpc_error",
        code: json.error.code,
        message: json.error.message,
        data: json.error.data,
      };
    }

    return {
      kind: "ok",
      value: {
        blockhash: json.result.value.blockhash,
        last_valid_block_height: json.result.value.lastValidBlockHeight,
      },
    };
  }

  /**
   * AC-02: getBalance — returns typed u64 balance.
   */
  async getBalance(pubkey: string): Promise<RpcResult<number>> {
    const id = this.nextId++;
    const payload = JSON.stringify({
      jsonrpc: "2.0",
      id,
      method: "getBalance",
      params: [pubkey, { commitment: "confirmed" }],
    });

    const raw = await this.transport.postJson(this.endpoint, payload);
    const json = JSON.parse(raw);

    if (json.error) {
      return {
        kind: "rpc_error",
        code: json.error.code,
        message: json.error.message,
        data: json.error.data,
      };
    }

    return { kind: "ok", value: json.result.value };
  }

  /**
   * AC-03: simulateTransaction — preserves raw JSON, no forced convergence.
   * AC-06: payload carries "sigVerify": true.
   */
  async simulateTransaction(
    encodedTx: string
  ): Promise<RpcResult<OwnedJson>> {
    const id = this.nextId++;
    const payload = JSON.stringify({
      jsonrpc: "2.0",
      id,
      method: "simulateTransaction",
      params: [
        encodedTx,
        {
          encoding: "base64",
          sigVerify: true, // AC-06: MUST be true for K3-F1 failure path
          commitment: "confirmed",
        },
      ],
    });

    const raw = await this.transport.postJson(this.endpoint, payload);
    const json = JSON.parse(raw);

    if (json.error) {
      return {
        kind: "rpc_error",
        code: json.error.code,
        message: json.error.message,
        data: json.error.data,
      };
    }

    return {
      kind: "ok",
      value: {
        value: json.result.value,
        raw,
      },
    };
  }

}
