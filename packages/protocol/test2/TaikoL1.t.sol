// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {AddressManager} from "../contracts/thirdparty/AddressManager.sol";
import {TaikoConfig} from "../contracts/L1/TaikoConfig.sol";
import {TaikoData} from "../contracts/L1/TaikoData.sol";
import {TaikoL1} from "../contracts/L1/TaikoL1.sol";
import {TaikoToken} from "../contracts/L1/TaikoToken.sol";
import {SignalService} from "../contracts/signal/SignalService.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {TaikoL1TestBase} from "./TaikoL1TestBase.sol";
import {LibProposing} from "../contracts/L1/libs/LibProposing.sol";

contract TaikoL1WithConfig is TaikoL1 {
    function getConfig()
        public
        pure
        override
        returns (TaikoData.Config memory config)
    {
        config = TaikoConfig.getConfig();

        config.enableTokenomics = true;
        config.bootstrapDiscountHalvingPeriod = 0;
        config.constantFeeRewardBlocks = 0;
        config.txListCacheExpiry = 5 minutes;
        config.proposerDepositPctg = 0;
        config.maxVerificationsPerTx = 0;
        config.enableSoloProposer = false;
        config.enableOracleProver = false;
        config.maxNumProposedBlocks = 11;
        config.maxNumVerifiedBlocks = 40;
        // this value must be changed if `maxNumProposedBlocks` is changed.
        config.slotSmoothingFactor = 4160;
        config.anchorTxGasLimit = 180000;

        config.proposingConfig = TaikoData.FeeConfig({
            avgTimeMAF: 64,
            avgTimeCap: 10 minutes * 1000,
            gracePeriodPctg: 100,
            maxPeriodPctg: 400,
            multiplerPctg: 400
        });

        config.provingConfig = TaikoData.FeeConfig({
            avgTimeMAF: 64,
            avgTimeCap: 10 minutes * 1000,
            gracePeriodPctg: 100,
            maxPeriodPctg: 400,
            multiplerPctg: 400
        });
    }
}

contract Verifier {
    fallback(bytes calldata) external returns (bytes memory) {
        return bytes.concat(keccak256("taiko"));
    }
}

contract TaikoL1Test is TaikoL1TestBase {
    function deployTaikoL1() internal override returns (TaikoL1 taikoL1) {
        taikoL1 = new TaikoL1WithConfig();
    }

    function setUp() public override {
        TaikoL1TestBase.setUp();
        _registerAddress(
            string(abi.encodePacked("verifier_", uint16(100))),
            address(new Verifier())
        );
    }

    /// @dev Test we can propose, prove, then verify more blocks than 'maxNumProposedBlocks'
    function test_more_blocks_than_ring_buffer_size() external {
        _depositTaikoToken(Alice, 1E6, 100);
        _depositTaikoToken(Bob, 1E6, 100);
        _depositTaikoToken(Carol, 1E6, 100);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        for (
            uint256 blockId = 1;
            blockId < conf.maxNumProposedBlocks * 10;
            blockId++
        ) {
            printVariables("before propose");
            TaikoData.BlockMetadata memory meta = proposeBlock(Alice, 1024);
            printVariables("after propose");
            mine(1);

            bytes32 blockHash = bytes32(1E10 + blockId);
            bytes32 signalRoot = bytes32(1E9 + blockId);
            proveBlock(Bob, meta, parentHash, blockHash, signalRoot);
            verifyBlock(Carol, 1);
            parentHash = blockHash;
        }
        printVariables("");
    }

    /// @dev Test more than one block can be proposed, proven, & verified in the
    ///      same L1 block.
    function test_multiple_blocks_in_one_L1_block() external {
        _depositTaikoToken(Alice, 1000, 1000);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        for (uint256 blockId = 1; blockId <= 2; blockId++) {
            printVariables("before propose");
            TaikoData.BlockMetadata memory meta = proposeBlock(Alice, 1024);
            printVariables("after propose");

            bytes32 blockHash = bytes32(1E10 + blockId);
            bytes32 signalRoot = bytes32(1E9 + blockId);
            proveBlock(Alice, meta, parentHash, blockHash, signalRoot);
            verifyBlock(Alice, 2);
            parentHash = blockHash;
        }
        printVariables("");
    }

    /// @dev Test verifying multiple blocks in one transaction
    function test_verifying_multiple_blocks_once() external {
        _depositTaikoToken(Alice, 1E6, 100);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        for (
            uint256 blockId = 1;
            blockId <= conf.maxNumProposedBlocks - 1;
            blockId++
        ) {
            printVariables("before propose");
            TaikoData.BlockMetadata memory meta = proposeBlock(Alice, 1024);
            printVariables("after propose");

            bytes32 blockHash = bytes32(1E10 + blockId);
            bytes32 signalRoot = bytes32(1E9 + blockId);
            proveBlock(Alice, meta, parentHash, blockHash, signalRoot);
            parentHash = blockHash;
        }
        verifyBlock(Alice, conf.maxNumProposedBlocks - 2);
        printVariables("after verify");
        verifyBlock(Alice, conf.maxNumProposedBlocks);
        printVariables("after verify");
    }

    /// @dev Test block timeincrease and fee shall decrease.
    function test_block_time_increases_but_fee_decreases() external {
        _depositTaikoToken(Alice, 1E6, 100);
        _depositTaikoToken(Bob, 1E6, 100);
        _depositTaikoToken(Carol, 1E6, 100);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        for (
            uint256 blockId = 1;
            blockId < conf.maxNumProposedBlocks * 10;
            blockId++
        ) {
            printVariables("before propose");
            TaikoData.BlockMetadata memory meta = proposeBlock(Alice, 1024);
            mine(1);

            bytes32 blockHash = bytes32(1E10 + blockId);
            bytes32 signalRoot = bytes32(1E9 + blockId);
            proveBlock(Bob, meta, parentHash, blockHash, signalRoot);
            verifyBlock(Carol, 1);
            mine(blockId);
            parentHash = blockHash;
        }
        printVariables("");
    }

    /// @dev Test block time goes down lover time and the fee should remain
    // the same.
    function test_block_time_decreases_but_fee_remains() external {
        _depositTaikoToken(Alice, 1E6, 100);
        _depositTaikoToken(Bob, 1E6, 100);
        _depositTaikoToken(Carol, 1E6, 100);

        bytes32 parentHash = GENESIS_BLOCK_HASH;

        uint256 total = conf.maxNumProposedBlocks * 10;

        for (uint256 blockId = 1; blockId < total; blockId++) {
            printVariables("before propose");
            TaikoData.BlockMetadata memory meta = proposeBlock(Alice, 1024);
            mine(1);

            bytes32 blockHash = bytes32(1E10 + blockId);
            bytes32 signalRoot = bytes32(1E9 + blockId);
            proveBlock(Bob, meta, parentHash, blockHash, signalRoot);
            verifyBlock(Carol, 1);
            mine(total + 1 - blockId);
            parentHash = blockHash;
        }
        printVariables("");
    }

    function propose_a_block_mechanism()
        internal
        returns (TaikoData.BlockMetadata memory metaInTheProtocol)
    {
        printVariables("before propose");

        uint32 gasLimit = 1000000;
        bytes memory txList = new bytes(1024);
        // This is the 1st parameter in the TaikoL1.sol's proposeBlock()
        // This is what the the actual block header must satisfy.
        TaikoData.BlockMetadataInput memory input = TaikoData
            .BlockMetadataInput({
                beneficiary: Alice,
                gasLimit: gasLimit,
                txListHash: keccak256(txList),
                txListByteStart: 0,
                txListByteEnd: 1024,
                cacheTxListInfo: 0
            });

        // This way we can access the 'nextBlockId' which is needed in the metadata
        TaikoData.StateVariables memory variables = L1.getStateVariables();

        uint256 _mixHash;
        unchecked {
            _mixHash = block.prevrandao * variables.numBlocks;
        }

        // Here what it does is "mocking" and copying in metaInTheProtocol
        // what will be in the protocol

        // nextBlockId : filled by the protocol SC
        metaInTheProtocol.id = variables.numBlocks;
        // lHeight : filled (exact same way) by the protocol SC
        metaInTheProtocol.l1Height = uint64(block.number - 1);
        // l1Hash : filled (exact same way) by the protocol SC
        metaInTheProtocol.l1Hash = blockhash(block.number - 1);
        // beneficiary : msg.sender
        metaInTheProtocol.beneficiary = Alice;
        // txListHash: hash of the TXN list (hash of the 2nd argument of the L1.proposeBlock())
        metaInTheProtocol.txListHash = keccak256(txList);
        // mixHash : since multiple L2 blocks might go into L1 block, we need to provide a semi-random hash for them to rely on
        metaInTheProtocol.mixHash = bytes32(_mixHash);
        // gasLimit: part of the (encoded) input (metadata)
        metaInTheProtocol.gasLimit = uint32(gasLimit);
        // Block timestamp, coming from the protocol SC
        metaInTheProtocol.timestamp = uint64(block.timestamp);

        // Let Alice send this proposeBlockTransaction()
        vm.prank(Alice, Alice);
        L1.proposeBlock(abi.encode(input), txList);

        mine(1);

        printVariables(
            "after propose but not yet proved so vars.lastBlockId not updated"
        );
    }

    /// @dev Test we cannot propose if input metadata is invalid
    function test_propose_with_invalid_metadata() public {
        _depositTaikoToken(Alice, 1E6, 100);

        uint32 gasLimit = 6000000;
        bytes memory txList = new bytes(1024);

        // Input
        TaikoData.BlockMetadataInput memory input = TaikoData
            .BlockMetadataInput({
                beneficiary: address(0),
                gasLimit: gasLimit,
                txListHash: keccak256(txList),
                txListByteStart: 0,
                txListByteEnd: 1024,
                cacheTxListInfo: 0
            });

        // beneficiary is 0 address - so should revert with invalid metadata
        vm.prank(Alice, Alice);
        vm.expectRevert(LibProposing.L1_INVALID_METADATA.selector);
        L1.proposeBlock(abi.encode(input), txList);

        // beneficiary is 0 address - so should revert with invalid metadata as well
        input.gasLimit = gasLimit + 1;

        vm.prank(Alice, Alice);
        vm.expectRevert(LibProposing.L1_INVALID_METADATA.selector);
        L1.proposeBlock(abi.encode(input), txList);
    }

    /// @dev Test we cannot propose more if we have 'maxNumProposedBlocks' unverified
    function test_propose_but_too_many_blocks() public {
        _depositTaikoToken(Alice, 1E6, 100);
        bytes memory txList = new bytes(1024);

        for (
            uint256 proposed = 0;
            proposed < conf.maxNumProposedBlocks - 1;
            proposed++
        ) {
            proposeBlock(Alice, 1024);
            mine(1);
        }

        TaikoData.BlockMetadataInput memory input = TaikoData
            .BlockMetadataInput({
                beneficiary: Alice,
                gasLimit: 10,
                txListHash: keccak256(txList),
                txListByteStart: 0,
                txListByteEnd: 1024,
                cacheTxListInfo: 0
            });

        // Too many block, so next one should revert
        vm.prank(Alice, Alice);
        vm.expectRevert(LibProposing.L1_TOO_MANY_BLOCKS.selector);
        L1.proposeBlock(abi.encode(input), txList);
    }

    /// @dev Test all issues related to txList
    function test_propose_but_txn_list_has_issues() public {
        _depositTaikoToken(Alice, 1E6, 100);

        bytes memory txList = new bytes(120001);

        TaikoData.BlockMetadataInput memory input = TaikoData
            .BlockMetadataInput({
                beneficiary: Alice,
                gasLimit: 10,
                txListHash: keccak256(txList),
                txListByteStart: 0,
                txListByteEnd: 120001,
                cacheTxListInfo: 0
            });

        // Too big
        vm.prank(Alice, Alice);
        vm.expectRevert(LibProposing.L1_TX_LIST.selector);
        L1.proposeBlock(abi.encode(input), txList);

        // ByteStart is beyond ByteEnd
        txList = new bytes(1024);
        input.txListByteEnd = 0;
        input.txListByteStart = 1;

        vm.prank(Alice, Alice);
        vm.expectRevert(LibProposing.L1_TX_LIST_RANGE.selector);
        L1.proposeBlock(abi.encode(input), txList);
    }
}
