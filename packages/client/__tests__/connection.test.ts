/**
 * Connection tests — mock transport, typed responses, AC-06 sigVerify assertion.
 */

import { describe, it, expect } from "vitest";
import { Connection } from "../src/connection.js";
import type { Transport } from "../src/types.js";

// --- Mock transport that captures requests and returns scripted responses ---

function createMockTransport(responses: string[]): {
  transport: Transport;
  captured: { url: string; payload: string }[];
} {
  let callIndex = 0;
  const captured: { url: string; payload: string }[] = [];

  const transport: Transport = {
    async postJson(url: string, payload: string): Promise<string> {
      captured.push({ url, payload });
      if (callIndex >= responses.length) {
        throw new Error("No more scripted responses");
      }
      return responses[callIndex++];
    },
  };

  return { transport, captured };
}

// --- Scripted RPC responses (mirrors devnet_e2e.zig) ---

const MOCK_BLOCKHASH_RESPONSE = JSON.stringify({
  jsonrpc: "2.0",
  id: 1,
  result: {
    context: { slot: 100 },
    value: {
      blockhash: "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn",
      lastValidBlockHeight: 1000,
    },
  },
});

const MOCK_SIMULATE_HAPPY = JSON.stringify({
  jsonrpc: "2.0",
  id: 2,
  result: {
    context: { slot: 100 },
    value: { err: null, logs: ["Program log: success"], unitsConsumed: 100 },
  },
});

const MOCK_SIMULATE_FAILURE = JSON.stringify({
  jsonrpc: "2.0",
  id: 2,
  error: {
    code: -32002,
    message: "Transaction signature verification failure",
    data: { err: "SignatureFailure" },
  },
});

const MOCK_BALANCE_RESPONSE = JSON.stringify({
  jsonrpc: "2.0",
  id: 1,
  result: { context: { slot: 100 }, value: 1000000000 },
});

// --- Tests ---

describe("Connection", () => {
  describe("AC-01: transport injection", () => {
    it("accepts injected transport via constructor", async () => {
      const { transport, captured } = createMockTransport([
        MOCK_BLOCKHASH_RESPONSE,
      ]);
      const conn = new Connection("http://mock.test", transport);

      const result = await conn.getLatestBlockhash();
      expect(result.kind).toBe("ok");
      expect(captured).toHaveLength(1);
      expect(captured[0].url).toBe("http://mock.test");
    });

    it("accepts injected transport via initWithTransport", async () => {
      const { transport, captured } = createMockTransport([
        MOCK_BLOCKHASH_RESPONSE,
      ]);
      const conn = Connection.initWithTransport("http://mock.test", transport);

      const result = await conn.getLatestBlockhash();
      expect(result.kind).toBe("ok");
      expect(captured).toHaveLength(1);
    });
  });

  describe("AC-02: getLatestBlockhash typed response", () => {
    it("returns typed LatestBlockhash with correct fields", async () => {
      const { transport } = createMockTransport([MOCK_BLOCKHASH_RESPONSE]);
      const conn = new Connection("http://mock.test", transport);

      const result = await conn.getLatestBlockhash();
      expect(result.kind).toBe("ok");
      if (result.kind === "ok") {
        expect(result.value.blockhash).toBe(
          "4sGjMW1sUnHzSxGspuhpqLDx6wiyjNtZAMdL4VZHirAn"
        );
        expect(result.value.last_valid_block_height).toBe(1000);
      }
    });
  });

  describe("AC-03: simulateTransaction preserves raw JSON", () => {
    it("returns OwnedJson with value and raw fields", async () => {
      const { transport } = createMockTransport([MOCK_SIMULATE_HAPPY]);
      const conn = new Connection("http://mock.test", transport);

      const result = await conn.simulateTransaction("base64encoded==");
      expect(result.kind).toBe("ok");
      if (result.kind === "ok") {
        expect(result.value.value).toBeDefined();
        expect(result.value.value.err).toBeNull();
        expect(result.value.raw).toContain("Program log: success");
      }
    });

    it("returns rpc_error for failure responses", async () => {
      const { transport } = createMockTransport([MOCK_SIMULATE_FAILURE]);
      const conn = new Connection("http://mock.test", transport);

      const result = await conn.simulateTransaction("base64encoded==");
      expect(result.kind).toBe("rpc_error");
      if (result.kind === "rpc_error") {
        expect(result.code).toBe(-32002);
        expect(result.message).toBe(
          "Transaction signature verification failure"
        );
      }
    });
  });

  describe("AC-06: simulateTransaction payload carries sigVerify=true", () => {
    it("includes sigVerify: true in RPC payload", async () => {
      const { transport, captured } = createMockTransport([
        MOCK_SIMULATE_HAPPY,
      ]);
      const conn = new Connection("http://mock.test", transport);

      await conn.simulateTransaction("dummybase64==");

      expect(captured).toHaveLength(1);
      const payload = JSON.parse(captured[0].payload);
      expect(payload.method).toBe("simulateTransaction");
      expect(payload.params[1].sigVerify).toBe(true);
    });
  });

  describe("AC-07: endpoint is configurable", () => {
    it("uses the provided endpoint for all requests", async () => {
      const { transport, captured } = createMockTransport([
        MOCK_BLOCKHASH_RESPONSE,
        MOCK_BALANCE_RESPONSE,
      ]);
      const customEndpoint = "http://127.0.0.1:8899";
      const conn = new Connection(customEndpoint, transport);

      await conn.getLatestBlockhash();
      await conn.getBalance("11111111111111111111111111111111");

      expect(captured[0].url).toBe(customEndpoint);
      expect(captured[1].url).toBe(customEndpoint);
    });
  });

  describe("getBalance", () => {
    it("returns typed balance value", async () => {
      const { transport } = createMockTransport([MOCK_BALANCE_RESPONSE]);
      const conn = new Connection("http://mock.test", transport);

      const result = await conn.getBalance(
        "11111111111111111111111111111111"
      );
      expect(result.kind).toBe("ok");
      if (result.kind === "ok") {
        expect(result.value).toBe(1000000000);
      }
    });
  });
});
