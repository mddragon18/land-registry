# **Blockchain-Based Land Registry System**

A decentralized system for recording land ownership, property registration, and property transfer approvals using multi-role governance, document verification and on-chain audit trails.

---

## **Overview**

Traditional land registry systems rely heavily on manual verification, paper documents and centralized databases. These are susceptible to tampering, corruption and data loss.

This project provides a blockchain-based land registry built on Ethereum (or any EVM chain) using Solidity + Foundry.
The goal is to record property ownership and changes transparently, immutably, and with proper verification steps enforced by smart-contract logic.

---

## **Core Features**

### **1. Multi-Role Governance**

The system defines three main roles:

* **Admin** — appoints Notaries and Registrars
* **Notary** — verifies ownership/transfer documents
* **Registrar** — final authority; approves final ownership change only after verifying off-chain payment receipt

These roles cannot overlap unless the Admin assigns multiple roles to the same address.

---

### **2. Two-Phase Approval System**

#### **A. Property Registration**

1. **Owner requests property registration** and uploads supporting files to IPFS.
2. **Notary approves registration documents** after reviewing them off-chain.
3. **Registrar finalizes registration**, updating the property owner.

#### **B. Property Transfer**

1. **Current owner initiates transfer request** to a new owner, attaching required documents.
2. **Notary verifies the documents** (sale deed, tax receipt, survey map, etc.).
3. **Registrar verifies payment**, records payment receipt CID (bank payment, offline), and finalizes transfer.

---

## **Smart Contract Summary**

### **Property Ownership**

* Ownership is stored on-chain as `owners[propertyId] → address`.
* Transfers only occur after:

  * a valid transfer request
  * notary document approval
  * registrar records payment receipt
  * registrar authorizes transfer

### **Requests**

Each property has one active or historical request stored in:

```
requests[propertyId]
```

Each request records:

* propertyId
* requester (initiator)
* current owner (snapshot)
* pending owner
* document CIDs (array)
* approval status
* payment receipt CID
* timestamps
* request stage

### **Documents**

All documents (deeds, tax receipts, survey maps, payment proof, etc.) are stored off-chain in IPFS.
Only their immutable CIDs are stored on-chain.

---

## **Contract Roles**

The contract uses OpenZeppelin’s `AccessControl` module.

| Role                   | Responsibility                                     |
| ---------------------- | -------------------------------------------------- |
| **DEFAULT_ADMIN_ROLE** | Grants/revokes other roles                         |
| **NOTARY_ROLE**        | Approves registration/transfer documents           |
| **REGISTRAR_ROLE**     | Finalizes registration and transfers after payment |

---

## **Approval Workflow Summary**

### **Property Registration**

1. **Owner → requestRegistration(propertyId, docs[])**

   * Status: PendingRegistration
2. **Notary → approveRegistrationDocs(propertyId)**

   * Marks docsApproved = true
3. **Registrar → finalizeRegistration(propertyId)**

   * Ownership assigned to requester
   * Status: Registered

---

### **Property Transfer**

1. **Current Owner → requestTransfer(propertyId, newOwner, docs[])**

   * Status: PendingTransfer
2. **Notary → approveTransferDocs(propertyId)**

   * Marks docsApproved = true
3. **Registrar → recordPaymentAndFinalize(propertyId, paymentReceiptCID)**

   * Records payment receipt
   * Assigns new owner
   * Status: Registered

---

## **Events Emitted**

The system emits multiple events to track the full lifecycle:

| Event                | Description                                         |
| -------------------- | --------------------------------------------------- |
| `RequestCreated`     | Owner/buyer created a registration/transfer request |
| `DocsApproved`       | Notary approved document set                        |
| `PaymentRecorded`    | Registrar stored bank receipt CID                   |
| `TransferFinalized`  | Ownership changed after registrar approval          |
| `PropertyRegistered` | New land registered to an owner                     |

These events can be indexed to build a transparency dashboard or audit log.

---

## **Running the Project (Foundry)**

### **1. Install Foundry**

```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### **2. Install Dependencies**

```
forge install OpenZeppelin/openzeppelin-contracts
```

### **3. Compile Contracts**

```
forge build
```

### **4. Run Tests**

```
forge test -vvv
```

### **5. Deploy Script (example)**

Create a file in `script/Deploy.s.sol`, then run:

```
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <KEY> --broadcast
```

---

## **IPFS Integration**

### How documents are handled:

1. Owner uploads files to IPFS using:

   * Pinata
   * nft.storage
   * or local IPFS CLI
2. Gets CIDs (strings like `Qm...`).
3. Passes an array of CIDs to:

   * `requestRegistration()` OR
   * `requestTransfer()`

The smart contract never stores the file, only the hash (CID).

---

## **Why This Design Is Realistic**

This mimics real government processes:

* Notaries only verify documents; they do *not* finalize transfers.
* Registrars finalize transfers only after confirming payment (bank receipts).
* Transfers cannot occur automatically; human verification is required at multiple steps.
* Every action is logged and traceable permanently on-chain.
* Documents can’t be faked because CIDs are immutable content-addressed hashes.

This makes the system trustworthy while preserving real-world manual checks where they actually matter.

---

## **Security Considerations**

* Access control prevents unauthorized approvals.
* All mutation actions require the proper role.
* Payment receipts are only accepted from registrar after off-chain validation.
* No on-chain payment handling avoids external financial integration complexity.
* Events ensure full transparency for audits.

---

## **Future Enhancements**

* Multi-notary quorum approval
* Escrow contract for on-chain payments
* Dispute/encumbrance lock flags
* Historical request tracking (multiple requests per property)
* Zero-knowledge proofs for document redaction
* Frontend dashboard for interacting with contract

---

## **Project Structure**

```
/
|─ src/
│   └─ LandRegistry.sol
|─ test/
│   └─ LandRegistry.t.sol
|─ script/
│   └─ Deploy.s.sol
├─ foundry.toml
└─ README.md
```

---

