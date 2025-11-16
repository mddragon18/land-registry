// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract LandRegistry is AccessControl {
    bytes32 public constant NOTARY_ROLE = keccak256("NOTARY_ROLE");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    enum PropertyStatus {
        None,
        PendingRegistration,
        Registered,
        PendingTransfer
    }

    struct Request {
        uint256 propertyId;
        address requester; // who initiated request (owner or buyer)
        address currentOwner; // snapshot of current owner at request time
        address pendingOwner; // new owner for transfer
        string[] docCIDs; // docs provided for this request (deed, tax, survey, etc)
        bool docsApproved; // set by notary
        string paymentReceiptCID; // bank payment receipt (set by requester or registrar)
        uint256 requestedAt;
        uint256 docsApprovedAt;
        uint256 finalizedAt;
        PropertyStatus status;
    }

    // property -> exists and current owner
    mapping(uint256 => address) public owners;
    // property -> latest request
    mapping(uint256 => Request) public requests;

    event RequestCreated(
        uint256 indexed propertyId, address indexed requester, address indexed pendingOwner, uint256 when
    );
    event DocsApproved(uint256 indexed propertyId, address indexed notary, uint256 when);
    event PaymentRecorded(uint256 indexed propertyId, string paymentCid, uint256 when);
    event TransferFinalized(uint256 indexed propertyId, address indexed from, address indexed to, uint256 when);
    event PropertyRegistered(uint256 indexed propertyId, address indexed owner, uint256 when);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // -------------------- Admin --------------------
    function addNotary(address _notary) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(NOTARY_ROLE, _notary);
    }

    function removeNotary(address _notary) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(NOTARY_ROLE, _notary);
    }

    function addRegistrar(address _registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(REGISTRAR_ROLE, _registrar);
    }

    function removeRegistrar(address _registrar) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(REGISTRAR_ROLE, _registrar);
    }

    // -------------------- Registration flow --------------------
    // Owner requests first-time registration (no payment enforced here by default)
    function requestRegistration(uint256 propertyId, string[] calldata docCIDs) external {
        require(owners[propertyId] == address(0), "Property already has an owner");
        Request storage r = requests[propertyId];
        require(
            r.status == PropertyStatus.None || r.status == PropertyStatus.PendingRegistration,
            "Another request in progress"
        );

        // overwrite/initialize request
        delete r.docCIDs;
        for (uint256 i = 0; i < docCIDs.length; i++) {
            r.docCIDs.push(docCIDs[i]);
        }

        r.propertyId = propertyId;
        r.requester = msg.sender;
        r.currentOwner = address(0);
        r.pendingOwner = msg.sender;
        r.docsApproved = false;
        r.paymentReceiptCID = "";
        r.requestedAt = block.timestamp;
        r.docsApprovedAt = 0;
        r.finalizedAt = 0;
        r.status = PropertyStatus.PendingRegistration;

        emit RequestCreated(propertyId, msg.sender, msg.sender, block.timestamp);
    }

    // Notary approves registration docs
    function approveRegistrationDocs(uint256 propertyId) external onlyRole(NOTARY_ROLE) {
        Request storage r = requests[propertyId];
        require(r.status == PropertyStatus.PendingRegistration, "No pending registration");
        require(!r.docsApproved, "Docs already approved");

        r.docsApproved = true;
        r.docsApprovedAt = block.timestamp;

        emit DocsApproved(propertyId, msg.sender, block.timestamp);
    }

    // Registrar finalizes registration, optionally checking paymentReceiptCID if needed
    // For simple register -> registrar finalizes based on docs approved
    function finalizeRegistration(uint256 propertyId) external onlyRole(REGISTRAR_ROLE) {
        Request storage r = requests[propertyId];
        require(r.status == PropertyStatus.PendingRegistration, "No pending registration");
        require(r.docsApproved, "Docs not approved");
        require(owners[propertyId] == address(0), "Property already owned");

        owners[propertyId] = r.pendingOwner;
        r.finalizedAt = block.timestamp;
        r.status = PropertyStatus.Registered;

        emit PropertyRegistered(propertyId, r.pendingOwner, block.timestamp);
    }

    // -------------------- Transfer flow --------------------
    // Owner initiates a transfer request by providing docs (sale agreement, tax receipts, etc) and new owner address
    function requestTransfer(uint256 propertyId, address newOwner, string[] calldata docCIDs) external {
        require(owners[propertyId] != address(0), "Property not registered");
        require(msg.sender == owners[propertyId], "Only current owner can request transfer");
        Request storage r = requests[propertyId];
        require(r.status != PropertyStatus.PendingTransfer, "Transfer already pending");

        // reset and record docs
        delete r.docCIDs;
        for (uint256 i = 0; i < docCIDs.length; i++) {
            r.docCIDs.push(docCIDs[i]);
        }

        r.propertyId = propertyId;
        r.requester = msg.sender;
        r.currentOwner = owners[propertyId];
        r.pendingOwner = newOwner;
        r.docsApproved = false;
        r.paymentReceiptCID = "";
        r.requestedAt = block.timestamp;
        r.docsApprovedAt = 0;
        r.finalizedAt = 0;
        r.status = PropertyStatus.PendingTransfer;

        emit RequestCreated(propertyId, msg.sender, newOwner, block.timestamp);
    }

    // Notary approves the provided docs for pending transfer
    function approveTransferDocs(uint256 propertyId) external onlyRole(NOTARY_ROLE) {
        Request storage r = requests[propertyId];
        require(r.status == PropertyStatus.PendingTransfer, "No pending transfer");
        require(!r.docsApproved, "Docs already approved");
        r.docsApproved = true;
        r.docsApprovedAt = block.timestamp;
        emit DocsApproved(propertyId, msg.sender, block.timestamp);
    }

    // Registrar records payment receipt (CID) and then finalizes transfer. Registrar must ensure receipt is valid off-chain.
    // This design assumes the bank payment is done off-chain and a receipt is uploaded to IPFS; registrar verifies it off-chain then calls this.
    function recordPaymentAndFinalize(uint256 propertyId, string calldata paymentReceiptCID)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        Request storage r = requests[propertyId];
        require(r.status == PropertyStatus.PendingTransfer, "No pending transfer");
        require(r.docsApproved, "Docs not approved yet");
        require(bytes(paymentReceiptCID).length > 0, "Payment receipt CID required");

        // record payment
        r.paymentReceiptCID = paymentReceiptCID;
        emit PaymentRecorded(propertyId, paymentReceiptCID, block.timestamp);

        // finalize ownership change
        address from = owners[propertyId];
        owners[propertyId] = r.pendingOwner;
        r.finalizedAt = block.timestamp;
        r.status = PropertyStatus.Registered;
        r.pendingOwner = address(0);

        emit TransferFinalized(propertyId, from, owners[propertyId], block.timestamp);
    }

    // -------------------- Views / Helpers --------------------
    function getRequest(uint256 propertyId)
        external
        view
        returns (
            uint256 propertyIdOut,
            address requester,
            address currentOwner,
            address pendingOwner,
            string[] memory docCIDs,
            bool docsApproved,
            string memory paymentReceiptCID,
            uint256 requestedAt,
            uint256 docsApprovedAt,
            uint256 finalizedAt,
            PropertyStatus status
        )
    {
        Request storage r = requests[propertyId];
        return (
            r.propertyId,
            r.requester,
            r.currentOwner,
            r.pendingOwner,
            r.docCIDs,
            r.docsApproved,
            r.paymentReceiptCID,
            r.requestedAt,
            r.docsApprovedAt,
            r.finalizedAt,
            r.status
        );
    }

    function getOwner(uint256 propertyId) external view returns (address) {
        return owners[propertyId];
    }
}
