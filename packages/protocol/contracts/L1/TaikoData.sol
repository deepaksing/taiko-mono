// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.18;

library TaikoData {
    struct Config {
        uint256 chainId;
        uint256 maxNumProposedBlocks;
        uint256 ringBufferSize;
        uint256 maxNumVerifiedBlocks;
        // This number is calculated from maxNumProposedBlocks to make
        // the 'the maximum value of the multiplier' close to 20.0
        uint256 maxVerificationsPerTx;
        uint256 blockMaxGasLimit;
        uint256 maxTransactionsPerBlock;
        uint256 maxBytesPerTxList;
        uint256 minTxGasLimit;
        // Moving average factors
        uint256 txListCacheExpiry;
        uint64 proofTimeTarget;
        uint8 adjustmentQuotient;
        bool enableSoloProposer;
        bool enableOracleProver;
        bool enableTokenomics;
        bool skipZKPVerification;
        bool allowMinting;
        bool useTimeWeightedReward;
    }

    struct StateVariables {
        uint256 basefee;
        uint64 genesisHeight;
        uint64 genesisTimestamp;
        uint64 numBlocks;
        uint64 lastVerifiedBlockId;
        uint64 lastProposedAt;
    }

    // 3 slots
    struct BlockMetadataInput {
        bytes32 txListHash;
        address beneficiary;
        uint32 gasLimit;
        uint24 txListByteStart; // byte-wise start index (inclusive)
        uint24 txListByteEnd; // byte-wise end index (exclusive)
        uint8 cacheTxListInfo; // non-zero = True
    }

    // 6 slots
    // Changing this struct requires chaing LibUtils.hashMetadata accordingly.
    struct BlockMetadata {
        uint64 id;
        uint64 timestamp;
        uint64 l1Height;
        bytes32 l1Hash;
        bytes32 mixHash;
        bytes32 txListHash;
        uint24 txListByteStart;
        uint24 txListByteEnd;
        uint32 gasLimit;
        address beneficiary;
    }

    struct ZKProof {
        bytes data;
        uint16 verifierId;
    }

    struct BlockEvidence {
        TaikoData.BlockMetadata meta;
        ZKProof zkproof;
        bytes32 parentHash;
        bytes32 blockHash;
        bytes32 signalRoot;
        bytes32 graffiti;
        address prover;
        uint32 gasUsed;
    }

    // 3 slots
    struct ForkChoice {
        bytes32 blockHash;
        bytes32 signalRoot;
        uint64 provenAt;
        uint32 gasUsed;
        address prover;
    }

    // 4 slots
    struct Block {
        // ForkChoice storage are reusable
        mapping(uint256 forkChoiceId => ForkChoice) forkChoices;
        uint64 blockId;
        uint64 proposedAt;
        uint64 deposit;
        uint24 nextForkChoiceId;
        uint24 verifiedForkChoiceId;
        bytes32 metaHash;
        address proposer;
    }

    // This struct takes 9 slots.
    struct TxListInfo {
        uint64 validSince;
        uint24 size;
    }

    struct State {
        // Ring buffer for proposed blocks and a some recent verified blocks.
        mapping(uint256 blockId_mode_ringBufferSize => Block) blocks;
        // A mapping from (blockId, parentHash) to a reusable ForkChoice storage pointer.
        // solhint-disable-next-line max-line-length
        mapping(uint256 blockId => mapping(bytes32 parentHash => uint256 forkChoiceId)) forkChoiceIds;
        // TODO(dani): change to:
        // mapping(address account => uint64 balance) balances;
        mapping(address account => uint256 balance) balances;
        mapping(bytes32 txListHash => TxListInfo) txListInfo;
        // Cummulated proofTime for reward calculation - changed in verifyBlock()
        uint256 proofTimeIssued;
        // Changing baseFee for proving - changed in verifyBlock()
        uint256 basefee;
        // Changing accumulated time for proposing - changed in proposeBlock() and in verifyBlock()
        uint256 accProposedAt;
        // Treasury amount - changed in proposeBlock() and in verifyBlock()
        uint256 rewardPool;
        // Never or rarely changed
        uint64 genesisHeight;
        uint64 genesisTimestamp;
        uint64 __reserved1;
        // Changed when a block is proposed/finalized
        uint64 numBlocks;
        uint64 lastProposedAt; // Timestamp when the last block is proposed.
        uint64 __reserved3;
        uint64 __reserved4;
        // Changed when a block is proven/finalized
        uint64 lastVerifiedBlockId;
        // the proof time moving average, note that for each block, only the
        // first proof's time is considered.
        uint64 __reserved5;
        uint64 __reserved6;
        // Reserved
        uint256[43] __gap; // TODO(dani): recount
    }
}
