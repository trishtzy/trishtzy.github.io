---
layout: post
title:  "Rate limit by proof of work"
date:   2025-08-16 00:00:00 +0800
tags: [rpi, retail-price-improvement, pow, sha256, nonce, rate-limiting, websockets, redis, dex, trading-bots, trading, decentralized-exchanges, anti-bot, proof-of-work]
---

Trading platforms have increasingly adopted Retail Price Improvement (RPI) orders following Bybit's initial implementation[^1]. These orders benefit retail users by offering better prices than the best bid or ask in an orderbook, but they come with a crucial restriction: only retail users should be able to match against them. This creates an interesting technical challenge: how do we reliably identify retail users versus algorithmic traders?

In centralized exchanges like Bybit, this problem is relatively straightforward to solve since both algorithmic traders and retail users must complete KYC verification, providing clearer identity markers. However, decentralized exchanges face a much more complex challenge. Without mandatory identity verification, distinguishing between retail users and sophisticated trading bots becomes nearly impossible through traditional means.

This is where rate limiting through proof of work (PoW) offers a promising solution. By requiring clients to expend computational resources to prove their legitimacy, we can create a system where retail users can access RPI orders while making it prohibitively expensive for high-frequency trading bots to abuse them. The core principle is simple yet effective: make order submission computationally expensive enough to deter automated systems while remaining manageable for individual retail traders.

### Challenge stream (backend)

The proof-of-work system begins with the server continuously generating cryptographic challenges for clients to solve. Every 50ms, the server performs the following operations:

* Gets the current timestamp in milliseconds
* Generates a seed using sha256(SECRET, timestampMs)
* Determines the current system difficulty target
* Broadcasts the challenge to all connected websocket clients

To understand how difficulty works, imagine the hash space as a number line spanning from 0 to 2^256:

```text
0 ----[valid range]---- target ----[invalid range]---- 2^256
```

The target value represents the difficulty threshold—the lower the target, the harder the challenge becomes.

| Difficulty | Avg Time (ms) | Min (ms) | Max (ms) | Avg Attempts | Success Rate | Use Case |
|------------|---------------|----------|----------|--------------|--------------|-----------|
| 1          | 2.0           | 0        | 5        | 16.2         | 100%         | Testing/Dev |
| 2          | 5.2           | 5        | 7        | 219.0        | 100%         | Testing/Dev |
| 3          | 13.3          | 5        | 25       | 1551.5       | 100%         | Normal Ops |
| 4          | 296.3         | 6        | 755      | 42299.0      | 100%         | Very High Load |
| 5          | 7765.7        | 951      | 19429    | 1083716.8    | 100%         | Emergency |
| 6          | 17873.5       | 3544     | 26053    | 2487213.7    | 30%          | Emergency |

*Times measured in Chrome browser using hash-wasm - actual frontend performance[^2]

At difficulty 1, the target equals 2^252, creating a valid range of [0, 2^252) out of 2^256 total possible hash values. This gives a success probability of 2^252 / 2^256 = 1/16 = 6.25% per attempt. The benchmark confirms this: with a 6.25% success rate, we expect ~16 attempts to find a valid hash, matching the observed 16.2 average attempts. Each difficulty level reduces the target by 4 bits (16× smaller), explaining the exponential growth in the attempts column: 16.2 → 219.0 → 1551.5 → 42299.0.

#### Why 50ms intervals?

The 50ms challenge refresh rate serves a critical security purpose: it prevents pre-computation attacks. Without this frequent rotation, sophisticated attackers could potentially stockpile valid hash solutions during quiet periods and then rapidly submit multiple orders when market opportunities arise. By forcing clients to solve fresh challenges every 50ms, the system ensures that computational work must be performed in real-time.

Clients connect to the challenge stream via websocket at `wss://api.example.com/ws/challenges`, which broadcasts challenge messages in the following format:

```json
{
  "type": "challenge",
  "seed": "a3f2b8c9d4e5f6a7b8c9d0e1f2a3b4c5",
  "difficulty": 0x0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
  // Difficulty 4 means: 4 hex zeros = 4 × 4 = 16 zero bits
  "timestamp": 1701234567890
}
```

The seed generation process combines a server-side secret with the current timestamp to ensure both unpredictability and verifiability:

```go
 // secret := os.Getenv("POW_SECRET")
func generateSeed(secret string, timestampMs int64) string {
    message := fmt.Sprintf("%s%d", secret, timestampMs)
    hash := sha256.Sum256([]byte(message))
    return hex.EncodeToString(hash[:])
}
```

### PoW Computation (Frontend)

Once clients receive a challenge from the server, they must solve the computational puzzle to prove their legitimacy before submitting any orders. This process transforms the raw challenge into a valid proof-of-work solution.

The solving algorithm follows a straightforward brute-force approach: clients construct a message by concatenating `userAddress + seed + nonce`, compute the SHA-256 hash of this message, and increment the nonce until the resulting hash falls within the target difficulty range. When a valid solution is found, both the nonce and hash become the proof-of-work credentials.

```ts
// Example PoW computation
function computePoW(userAddress: string, seed: string, difficulty: string): {nonce: number, hash: string} | null {
  const target = new BigNumber(difficulty, 16); // difficulty is in hex
  // target = 2^(256 - 16) = 2^240
  for (let nonce = 0; nonce < 10000000; nonce++) {
    const message = `${userAddress}${seed}${nonce}`;
    const hash = hashWasm.sha256(message);
    const hashBN = new BigNumber(hash, 16);
    if (hashBN.isLessThan(target)) {
      return {nonce, hash};
    }
  }
  return null;
}
```

With a valid proof-of-work solution in hand, clients can now submit their trading orders along with the computational proof. The order payload includes both the standard trading parameters and the PoW credentials:

```json
{
  "order": {
    "symbol": "BTC/USDT",
    "side": "buy",
    "type": "limit",
    "quantity": "0.1",
    "price": "45000"
  },
  // ... existing api body request
  "pow": {
    "nonce": 487293, // the computed nonce
    "hash": "0000a8f3b2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8",
    "timestamp": 1701234567890 // needs to be the same as the one in the challenge message and it needs to be < 100ms from current time
  }
}
```

### PoW Verification (Backend)

The final piece of the puzzle involves server-side verification of submitted proof-of-work solutions. This critical step ensures that clients have genuinely performed the required computational work and haven't attempted to bypass the system through various attack vectors.

The verification process follows a multi-step validation approach:

* Confirms the challenge timestamp falls within the 100ms validity window
* Enforces the 3 orders/second rate limit for retail users
* Reconstructs the seed using the server secret and the provided timestamp
* Rebuilds the message format: userAddress + seed + nonce
* Computes SHA-256 and verifies it matches the submitted hash

To implement effective rate limiting, the system requires a high-performance key-value store like Redis. Each user's request rate is tracked using keys in the format `rate:{userAddress}:{timestampMs}` with a 2-second TTL for automatic cleanup.

```go
// Example verification of hash
func verifyPoW(userAddress string, pow PoWRequest, secret string) bool {
    // 1. Check timestamp is within 100ms
    if time.Now().UnixMilli() - pow.Timestamp > 100 {
        return false
    }

    // 2. Check rate limit: max 3 orders per second using fixed windows
    currentSecond := time.Now().Unix()
    rateLimitKey := fmt.Sprintf("rate:%s:%d", userAddress, currentSecond)

    // Increment counter for current second
    count, err := redisClient.Incr(ctx, rateLimitKey).Result()
    if err != nil {
        return false
    }

    // Set expiry on first increment
    if count == 1 {
        // 100K users: 200K keys stored max → ~25.6 MB
        redisClient.Expire(ctx, rateLimitKey, 2*time.Second) // to clean up old keys
    }

    // Check if limit exceeded
    if count > 3 {
        redisClient.Decr(ctx, rateLimitKey) // Rollback increment
        return false // Rate limit exceeded
    }

    // 3. Recompute seed from secret and timestamp
    seed := generateSeed(secret, pow.Timestamp)

    // 4. Reconstruct and verify hash
    message := fmt.Sprintf("%s%s%d", userAddress, seed, pow.Nonce)
    computedHash := sha256.Sum256([]byte(message))
    hexHash := hex.EncodeToString(computedHash[:])

    if hexHash != pow.Hash {
        return false
    }

    // 5. Check if hash meets difficulty target
    hashInt := new(big.Int)
    hashInt.SetString(pow.Hash, 16)

    target := getSystemDifficulty() // Returns current difficulty target
    return hashInt.Cmp(target) < 0 // hashInt < target
}
```

---

[^1]: <https://www.bybit.com/en/help-center/article/Retail-Price-Improvement-RPI-Order>
[^2]: Interactive SHA-256 benchmark available at: <https://gist.github.com/trishtzy/601be19d4ed18fd78da8d3228fe2dafb>
