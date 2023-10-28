// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solady/src/tokens/ERC721.sol";
import "solady/src/auth/Ownable.sol";
import "solady/src/utils/LibString.sol";
import "solady/src/utils/MerkleProofLib.sol";


error MintPriceNotPaid();
error NoWhiteList();
error MaxSupply();
error NonExistentTokenURI();
error NotInWhiteList();
error WithdrawTransfer();

contract NFT is ERC721, Ownable {
    using LibString for uint256;

    string private __name;
    string private __symbol;

    string public baseURI;
    bytes32 public merkleRoot;
    
    uint256 public currentTokenId;    
    uint256 public constant TOTAL_SUPPLY = 10_000;
    uint256 public constant MINT_PRICE = 0.08 ether;

    uint256 public wlCount;
    uint256 public constant WL_SUPPLY = 1_000;
    uint256 public constant WL_MINT_PRICE = 0.04 ether;

    constructor(string memory _name, string memory _symbol, string memory _baseURI, bytes32 _merkleRoot) {
        __name = _name;
        __symbol = _symbol;
        baseURI = _baseURI;
        merkleRoot = _merkleRoot;
        _initializeOwner(msg.sender);
    }
    
    function mintTo(address recipient) public payable returns (uint256) {
        if (msg.value < MINT_PRICE) {
            revert MintPriceNotPaid();
        }
        uint256 newTokenId = ++currentTokenId;
        if (newTokenId > TOTAL_SUPPLY) {
            revert MaxSupply();
        }
        _safeMint(recipient, newTokenId);
        return newTokenId;
    }

    function whitelistMint(address recipient, bytes32[] calldata _proof) public payable returns (uint256) {
        if (merkleRoot[0] == 0) {
            revert NoWhiteList();
        }
        if (!verifyAddress(msg.sender, _proof)) {
            revert NotInWhiteList();
        }
        if (msg.value < WL_MINT_PRICE) {
            revert MintPriceNotPaid();
        }
        uint256 totalWL = ++wlCount;
        if (totalWL > WL_SUPPLY) {
            revert MaxSupply();
        }
        uint256 newTokenId = ++currentTokenId;
        if (newTokenId > TOTAL_SUPPLY) {
            revert MaxSupply();
        }
        _safeMint(recipient, newTokenId);
        return newTokenId;
    } 

    function name() public view virtual override returns (string memory) {
        return __name;
    }

    function symbol() public view virtual override returns (string memory) {
        return __symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) {
            revert NonExistentTokenURI();
        }
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    function setBaseURI(string memory _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function withdrawPayments(address payable payee) external onlyOwner {
        uint256 balance = address(this).balance;
        (bool transferTx, ) = payee.call{value: balance}("");
        if (!transferTx) {
            revert WithdrawTransfer();
        }
    }

    function verifyAddress(address recipient, bytes32[] calldata _merkleProof) private view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(recipient));
        return MerkleProofLib.verify(_merkleProof, merkleRoot, leaf);
    }
}
