// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "murky/src/Merkle.sol";
import "../src/NFTContract.sol";
import "forge-std/console.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

contract NFTTest is Test {
    using stdStorage for StdStorage;

    bytes32[] private data;
    Merkle private merkle;
    NFT private nft;

    function setUp() public {
        merkle = new Merkle();
        data = new bytes32[](4);
        data[0] = keccak256(abi.encodePacked(address(0)));
        data[1] = keccak256(abi.encodePacked(address(1)));
        data[2] = keccak256(abi.encodePacked(address(2)));
        data[3] = keccak256(abi.encodePacked(address(3)));               
        
        nft = new NFT("NFT_tutorial", "TUT", "", merkle.getRoot(data));
    }

    function test_Pack() public {
        bytes32 leaf = keccak256(abi.encodePacked(address(1)));
        assertEq(leaf, data[1]);
    }

    function test_MerkleProof() public {
        bytes32[] memory proof = merkle.getProof(data, 2);
        bool verified = merkle.verifyProof(merkle.getRoot(data), proof, data[2]);
        assertTrue(verified);
    }

    function test_RevertMintWithoutValue() public {
        vm.expectRevert(MintPriceNotPaid.selector);
        nft.mintTo(address(1));
    }

    function test_RegisteredWhiteListMintPricePaid() public {
        vm.startPrank(address(2));
        vm.deal(address(2), 1 ether);
        nft.whitelistMint{value: 0.04 ether}(address(2), merkle.getProof(data, 2));
        vm.stopPrank();
    }

    function test_MintPricePaid() public {
        vm.prank(address(2));
        vm.deal(address(2), 1 ether);
        nft.mintTo{value: 0.08 ether}(address(2));
    }

    function test_MintPriceOverPaid() public {        
        vm.prank(address(2));
        vm.deal(address(2), 1 ether);
        nft.mintTo{value: 0.10 ether}(address(2));
    }

    function testFail_MintPriceUnderPaid() public {
        vm.prank(address(3));
        vm.deal(address(3), 0.07 ether);
        nft.mintTo{value: 0.07 ether}(address(3));
    }

    function test_RevertMintMaxSupplyReached() public {
        uint256 slot = stdstore
            .target(address(nft))
            .sig("currentTokenId()")
            .find();

        bytes32 loc = bytes32(slot);
        bytes32 mockedCurrentTokenId = bytes32(abi.encode(10000));
        vm.store(address(nft), loc, mockedCurrentTokenId);
        vm.expectRevert(MaxSupply.selector);
        nft.mintTo{value: 0.08 ether}(address(2));
    }

    function test_RevertMintToZeroAddress() public {
        vm.expectRevert("INVALID_RECIPIENT");
        nft.mintTo{value: 0.08 ether}(address(0));
    }

    function test_NewMintOwnerRegistered() public {
        nft.mintTo{value: 0.08 ether}(address(1));
        uint256 slotOfNewOwner = stdstore
            .target(address(nft))
            .sig(nft.ownerOf.selector)
            .with_key(1)
            .find();

        uint160 ownerOfTokenIdOne = uint160(
            uint256(
                (vm.load(address(nft), bytes32(abi.encode(slotOfNewOwner))))
            )
        );
        assertEq(address(ownerOfTokenIdOne), address(1));
    }

    function test_UpdateBaseURIAsOwner() public {
        nft.setBaseURI("ipfs://0x1234567890");
        assertEq(nft.baseURI(), "ipfs://0x1234567890");
    }

    function test_UpdateBaseURIAsNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xd3ad)));
        vm.prank(address(0xd3ad));
        nft.setBaseURI("ipfs://0x1234567890");                
    }

    function test_BalanceIncremented() public {
        vm.startPrank(address(1));
        vm.deal(address(1), 1 ether);
        nft.mintTo{value: 0.08 ether}(address(1));
        uint256 slotBalance = stdstore
            .target(address(nft))
            .sig(nft.balanceOf.selector)
            .with_key(address(1))
            .find();

        uint256 balanceFirstMint = uint256(
            vm.load(address(nft), bytes32(slotBalance))
        );
        assertEq(balanceFirstMint, 1);

        nft.mintTo{value: 0.08 ether}(address(1));
        uint256 balanceSecondMint = uint256(
            vm.load(address(nft), bytes32(slotBalance))
        );
        assertEq(balanceSecondMint, 2);
        vm.stopPrank();
    }

    function test_SafeContractReceiver() public {
        Receiver receiver = new Receiver();
        vm.startPrank(address(receiver));
        vm.deal(address(receiver), 1 ether);
        nft.mintTo{value: 0.08 ether}(address(receiver));
        uint256 slotBalance = stdstore
            .target(address(nft))
            .sig(nft.balanceOf.selector)
            .with_key(address(receiver))
            .find();

        uint256 balance = uint256(vm.load(address(nft), bytes32(slotBalance)));
        assertEq(balance, 1);
        vm.stopPrank();
    }

    function test_RevertUnSafeContractReceiver() public {
        // Adress set to 11, because first 10 addresses are restricted for precompiles
        vm.etch(address(11), bytes("mock code"));
        vm.expectRevert(bytes(""));
        nft.mintTo{value: 0.08 ether}(address(11));
    }

    function test_WithdrawalWorksAsOwner() public {        
        address payable payee = payable(address(0x1337));
        uint256 priorPayeeBalance = payee.balance;

        // Mint an NFT, sending eth to the contract
        vm.startPrank(address(2));
        vm.deal(address(2), 1 ether);
        nft.mintTo{value: nft.MINT_PRICE()}(address(2));
        vm.stopPrank();

        // Check that the balance of the contract is correct
        assertEq(address(nft).balance, nft.MINT_PRICE());
        uint256 nftBalance = address(nft).balance;

        // Withdraw the balance and assert it was transferred
        nft.withdrawPayments(payee);
        assertEq(payee.balance, priorPayeeBalance + nftBalance);        
    }

    function test_WithdrawalAsNotOwner() public {
        // Mint an NFT, sending eth to the contract
        Receiver receiver = new Receiver();
        vm.startPrank(address(receiver));
        vm.deal(address(receiver), 1 ether);
        nft.mintTo{value: nft.MINT_PRICE()}(address(2));
        // Check that the balance of the contract is correct
        assertEq(address(nft).balance, nft.MINT_PRICE());
        vm.stopPrank();

        // Confirm that a non-owner cannot withdraw
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xd3ad)));
        vm.startPrank(address(0xd3ad));
        nft.withdrawPayments(payable(address(0xd3ad)));
        vm.stopPrank();
    }
}

contract Receiver is ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
