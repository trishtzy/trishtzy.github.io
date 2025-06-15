---
layout: post
title:  "Bitcoin vs Ethereum Signature Schemes: A Deep Dive into Cryptographic Differences"
date:   2025-06-05 02:16:00 +0800
categories: [blockchain, cryptography, bitcoin, ethereum]
tags: [secp256k1, ecdsa, der-encoding, kms, gnosis-safe]
---

Recently, I had the opportunity to work on Gnosis Safe message signing with AWS KMS. The key setup in KMS typically uses an asymmetric `ECC_SECG_P256K1` (secp256k1) key type.

Sound familiar? Secp256k1 is the same elliptic curve used in Bitcoin's public-key cryptography. This presents an interesting opportunity to explore how Bitcoin and Ethereum handle signatures differently, despite using the same underlying cryptographic curve.

## Bitcoin Signature Scheme: DER Encoding in Action

Let's examine a real Bitcoin transaction to understand how signatures are structured. Consider transaction [612f92512f9f787848ff7c3c65d21dbe0d21da7823cfc5fe0673ced0ac08fcd0](https://mempool.space/tx/612f92512f9f787848ff7c3c65d21dbe0d21da7823cfc5fe0673ced0ac08fcd0), which uses a P2WPKH (Pay-to-Witness-Public-Key-Hash) script pattern.

To unlock a P2WPKH output, we need:

1. A valid ECDSA signature
2. The original public key in the witness field

Here's an example witness from input 2 of the above transaction:

```text
Signature: 3044022074dff6b6b37ea26a420279a2b47c64a6fa74e08054897db70d01c96496601d880220730710ac96a4ba9c6f8585013c058fdbc7a38f1661c881aa8f87427c0bd9dbe501

Public Key: 02364ac729251e391bda6240e2e85e899b233c9a6339b340afafa9e894f7dba39b
```

### DER Structure Breakdown

The signature is encoded using DER (Distinguished Encoding Rules) as described by ASN.1.[^1] Let's decode it step by step:

**SEQUENCE Header:**
- `30` - SEQUENCE tag (indicates DER-encoded sequence)[^2]
- `44` - Length of the entire signature (68 bytes in decimal)

**First Integer (r value):**
- `02` - INTEGER tag[^3]
- `20` - Length (32 bytes)
- `74dff6b6b37ea26a420279a2b47c64a6fa74e08054897db70d01c96496601d88` - The r value

**Second Integer (s value):**
- `02` - INTEGER tag
- `20` - Length (32 bytes)
- `730710ac96a4ba9c6f8585013c058fdbc7a38f1661c881aa8f87427c0bd9dbe5` - The s value

**SIGHASH Flag:**
- `01` - SIGHASH_ALL flag

The ECDSA signature consists of two 256-bit integers (r, s), and DER provides a standardized way to encode these along with their lengths and types. In DER encoding, `30` in hex (`00110000` in binary) indicates the start of a SEQUENCE structure.

> **Note**: The leading `00` byte in the r value would be added if needed because DER requires positive integers. Without it, a high bit would make the value appear negative in two's complement representation.

## Ethereum Signature Scheme: Compact and Recoverable

Ethereum takes a different approach with a more compact signature scheme. Unlike Bitcoin, Ethereum signatures don't require a separate public key field because **you can derive the public key from the transaction signature itself**.

Let's examine an Ethereum transaction using the `eth_getTransactionByHash` RPC call:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "blockHash": "0x949f40920a86f281daccbe8e30dd60a366b22ff270647815f6bfc0402ff38e42",
    "blockNumber": "0xce3",
    "from": "0x047347096a6dc73f8626afb520c383a02efda314",
    "gas": "0x15f90",
    "gasPrice": "0x4a817c800",
    "hash": "0x70a7552c8ab8d2621c80c8a1c149012d10a823c4619cc82235cbdfad0553310b",
    "input": "0x021df6f4000000000000000000000000000000000000000000000000000000000000000d48656c6c6f2c20776f726c642100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d48656c6c6f2c20776f726c642100000000000000000000000000000000000000",
    "nonce": "0x178",
    "to": "0xe2412bb63a0a25d7b8973fc6764fd246ebe62c7a",
    "transactionIndex": "0x0",
    "value": "0x0",
    "v": "0x1b",
    "r": "0xd693b532a80fed6392b428604171fb32fdbf953728a3a7ecc7d4062b1652c042",
    "s": "0x24e9c602ac800b983b035700a14b23f78a253ab762deab5dc27e3555a750b354"
  }
}
```

### Understanding the v Parameter

The `r`, `s`, and `v` values form the Ethereum signature. While Bitcoin signatures only have `r` and `s` values, Ethereum adds the `v` parameter as a **recovery ID** that allows us to recover the public key from the signature.

For modern Ethereum transactions using [EIP-155](https://eips.ethereum.org/EIPS/eip-155) (replay attack protection), the v value is calculated as:

```
v = {0,1} + CHAIN_ID * 2 + 35
```

The constant 35 prevents conflicts with legacy signatures.

For legacy signatures (pre-EIP-155), it would be:

```
v = {0,1} + 27
```

## Signing Ethereum Transaction with AWS KMS

Now that we understand the differences, how can we generate valid Ethereum signatures using AWS KMS with a secp256k1 key? Here's a practical implementation:

```go
package main

import (
    "context"
    "fmt"
    "log"
    "math/big"

    awsconfig "github.com/aws/aws-sdk-go-v2/config"
    "github.com/aws/aws-sdk-go-v2/service/kms"
    "github.com/ethereum/go-ethereum/common"
    "github.com/ethereum/go-ethereum/core/types"
    signer "github.com/welthee/go-ethereum-aws-kms-tx-signer/v2"
)

func main() {
    ctx := context.Background()
    cfg, err := awsconfig.LoadDefaultConfig(ctx)
    if err != nil {
        log.Fatal("Failed to load AWS default config:", err)
    }

    kmsClient := kms.NewFromConfig(cfg)
    keyID := "your-kms-key-id" // Replace with your actual KMS key ID
    chainID := big.NewInt(1)   // Ethereum mainnet

    transactor, err := signer.NewAwsKmsTransactorWithChainIDCtx(ctx, kmsClient, keyID, chainID)
    if err != nil {
        log.Fatal("Unable to initialize KMS transactor:", err)
    }

    // Configure transaction parameters
    transactor.GasLimit = uint64(21000)
    transactor.GasPrice = big.NewInt(20000000000) // 20 gwei

    to := common.HexToAddress("0xe2412bb63a0a25d7b8973fc6764fd246ebe62c7a")
    value := big.NewInt(1000000000000000000) // 1 ETH in wei
    gasLimit := uint64(21000)
    gasPrice := big.NewInt(20000000000)
    nonce := uint64(0) // Retrieve this from the network

    tx := types.NewTransaction(nonce, to, value, gasLimit, gasPrice, nil)
    signedTx, err := transactor.Signer(transactor.From, tx)
    if err != nil {
        log.Fatal("Failed to sign transaction:", err)
    }

    v, r, s := signedTx.RawSignatureValues()

    // Build 65-byte signature
    rBytes := make([]byte, 32)
    sBytes := make([]byte, 32)
    r.FillBytes(rBytes)
    s.FillBytes(sBytes)

    signature := make([]byte, 65)
    copy(signature[0:32], rBytes)   // R
    copy(signature[32:64], sBytes)  // S
    // signedTx has adjusted v values already according to the signer type determined in NewAwsKmsTransactorWithChainIDCtx
    signature[64] = byte(v.Uint64()) // V

    fmt.Printf("Ethereum signature: 0x%x\n", signature)
}
```

### Key Implementation Details

The [`go-ethereum-aws-kms-tx-signer`](https://github.com/welthee/go-ethereum-aws-kms-tx-signer) library handles several critical adjustments:

#### 1. EIP-2 Compliance (Transaction Malleability Prevention)

[EIP-2](https://eips.ethereum.org/EIPS/eip-2) addresses transaction malleability by enforcing canonical signatures:

> Allowing transactions with any s value with 0 < s < secp256k1n opens a transaction malleability concern, as one can take any transaction, flip the s value from s to secp256k1n - s, flip the v value (27 → 28, 28 → 27), and the resulting signature would still be valid.

The library ensures that the s value is in the "lower half" of the valid range:

```go
// Adjust S value according to Ethereum standard
sBigInt := new(big.Int).SetBytes(sBytes)
if sBigInt.Cmp(secp256k1HalfN) > 0 {
    // Convert to lower half: s = n - s
    sBytes = new(big.Int).Sub(secp256k1N, sBigInt).Bytes()
}
```

#### 2. Recovery ID Determination

The library's `getEthereumSignature` function determines the correct recovery ID (v) by:

1. **Preparing the base signature**: Concatenate r and s values, each padded to 32 bytes
2. **Testing recovery ID 0**: Try v=0 and attempt public key recovery
3. **Verifying recovered key**: Compare with expected public key
4. **Fallback to recovery ID 1**: If v=0 fails, try v=1

**Why only recovery IDs 0 and 1?**

Theoretically, ECDSA signatures can have up to 4 possible recovery candidates:

- **Recovery ID 0**: Point with x-coordinate = `r`, positive y
- **Recovery ID 1**: Point with x-coordinate = `r`, negative y
- **Recovery ID 2**: Point with x-coordinate = `r + n`, positive y (where n is curve order)
- **Recovery ID 3**: Point with x-coordinate = `r + n`, negative y

However, recovery IDs 2 and 3 are **extremely rare** with secp256k1[^4]. In practice, virtually all ECDSA signatures use recovery IDs 0 or 1, which is why the library only tests these two values.

#### 3. V value handling in go-ethereum

The `go-ethereum-aws-kms-tx-signer` library produces signatures with **v values of 0 or 1**, which represent the raw recovery IDs from the ECDSA signing process. The go-ethereum library then automatically adjusts these v values according to the signer type when creating the transaction.

```go
// From go-ethereum's WithSignature method
// This signature needs to be in the [R || S || V] format where V is 0 or 1.
func (tx *Transaction) WithSignature(signer Signer, sig []byte) (*Transaction, error) {
    r, s, v, err := signer.SignatureValues(tx, sig)
    if err != nil {
        return nil, err
    }
    cpy := tx.inner.copy()
    cpy.setSignatureValues(signer.ChainID(), v, r, s)
    return &Transaction{inner: cpy, time: tx.time}, nil
}
```

**For EIP-155 transactions** (with chain ID), the signer adjusts the v value:

```go
// EIP155Signer.SignatureValues
func (s EIP155Signer) SignatureValues(tx *Transaction, sig []byte) (R, S, V *big.Int, err error) {
    R, S, V = decodeSignature(sig)
    if s.chainId.Sign() != 0 {
        V = big.NewInt(int64(sig[64] + 35))  // v = {0,1} + 35
        V.Add(V, s.chainIdMul)              // + chainId * 2
    }
    return R, S, V, nil
}
```

**For legacy transactions** (pre-EIP-155), the adjustment is simpler:

```go
func decodeSignature(sig []byte) (r, s, v *big.Int) {
    r = new(big.Int).SetBytes(sig[:32])
    s = new(big.Int).SetBytes(sig[32:64])
    v = new(big.Int).SetBytes([]byte{sig[64] + 27})  // v = {0,1} + 27
    return r, s, v
}
```

This automatic adjustment means that when using the `go-ethereum-aws-kms-tx-signer` library for transaction hash calculation, developers don't need to manually handle v value conversions - the go-ethereum library handles the appropriate transformation based on whether the transaction uses EIP-155 or legacy signing.

However, if you just need the raw signature for other purposes (such as off-chain message signing), you can simply add 27 to the recovery ID to get the legacy Ethereum v value.

```go
if signature[64] == 0 || signature[64] == 1 {
    signature[64] += 27
}
```

## Conclusion

While Bitcoin and Ethereum both use secp256k1, their signature schemes differ fundamentally: Bitcoin uses DER-encoded signatures with explicit public keys, while Ethereum uses compact 65-byte signatures with recoverable public keys via the v parameter.

Understanding these differences is essential when integrating services like AWS KMS with Ethereum applications.

---

[^1]: ASN.1 (Abstract Syntax Notation One) is a standard interface description language for defining data structures that can be serialized and deserialized in a cross-platform way. For a comprehensive introduction, see [A Layman's Guide to a Subset of ASN.1, BER, and DER](https://luca.ntop.org/Teaching/Appunti/asn1.html).

[^2]: The SEQUENCE encoding rules in DER are detailed in [A Layman's Guide to a Subset of ASN.1, BER, and DER](https://luca.ntop.org/Teaching/Appunti/asn1.html).

[^3]: The INTEGER encoding rules in DER are explained in [A Layman's Guide to a Subset of ASN.1, BER, and DER](https://luca.ntop.org/Teaching/Appunti/asn1.html).

[^4]: libsecp256k1 source code comment: "The overflow condition is cryptographically unreachable as hitting it requires finding the discrete log of some P where P.x >= order, and only 1 in about 2^127 points meet this criteria." Available at: [https://github.com/bitcoin-core/secp256k1](https://github.com/bitcoin-core/secp256k1/blob/v0.6.0/src/ecdsa_impl.h#L280-L285)
