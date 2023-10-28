// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "solady/tokens/ERC721.sol";
import "solady/tokens/ERC2981.sol";
import "solady/auth/Ownable.sol";
import "solady/utils/LibString.sol";
import "solady/utils/MerkleProofLib.sol";

contract NFT is ERC721, ERC2981, Ownable {
    using LibString for uint256;

    error GeneralMintNotAllowed();
    error MaxSupply();
    error MintPriceNotPaid();
    error NonExistentTokenURI();
    error NotInWhiteList();
    error NoWhiteList();
    error WhiteListMintNotAllowed();
    error WithdrawTransfer();

    string private __name;
    string private __symbol;

    string public baseURI;
    bytes32 public merkleRoot;
    
    bool public allowGeneralMint = false;
    uint256 public currentTokenId;    
    uint256 public constant TOTAL_SUPPLY = 10_000;
    uint256 public constant MINT_PRICE = 0.08 ether;    

    bool public allowWhiteListMint = false;
    uint256 public whiteListCount;
    uint256 public constant WL_SUPPLY = 1_000;
    uint256 public constant WL_MINT_PRICE = 0.04 ether;

    // royaly percent divided by 10 --> 7_5 = 7.5%, 10 == 1%, 250 == 25%
    uint96 public constant ROYALTY_PERCENT = 7_5;

    constructor(string memory _name, string memory _symbol, string memory _baseURI, bytes32 _merkleRoot) {
        __name = _name;
        __symbol = _symbol;
        baseURI = _baseURI;
        merkleRoot = _merkleRoot;
        uint96 royaltyPercent = ROYALTY_PERCENT * 10;
        _setDefaultRoyalty(address(this), royaltyPercent);
        _initializeOwner(msg.sender);
    }
    
    function mintTo(address recipient) public payable returns (uint256[] memory) {
        return mintTo(recipient, 1);
    }

    function mintTo(address recipient, uint16 count) public payable returns (uint256[] memory) {
        if (!allowGeneralMint) {
            revert GeneralMintNotAllowed();
        }
        if (msg.value < (MINT_PRICE * count)) {
            revert MintPriceNotPaid();
        }
        if ((currentTokenId + count) > TOTAL_SUPPLY) {
            revert MaxSupply();
        }

        uint256[] memory tokens = new uint256[](count);
        for (uint16 i = 0; i < count; i++) {
            tokens[i] = ++currentTokenId;
            _safeMint(recipient, tokens[i]);
        }        
        return tokens;
    }

    function whiteListMintTo(address recipient, bytes32[] calldata _proof) public payable returns (uint256[] memory) {
        return whiteListMintTo(recipient, 1, _proof);
    }

    function whiteListMintTo(address recipient, uint16 count, bytes32[] calldata _proof) public payable returns (uint256[] memory) {
        if (!allowWhiteListMint) {
            revert WhiteListMintNotAllowed();
        }
        if (merkleRoot[0] == 0) {
            revert NoWhiteList();
        }
        if (!verifyAddress(msg.sender, _proof)) {
            revert NotInWhiteList();
        }
        if (msg.value < WL_MINT_PRICE) {
            revert MintPriceNotPaid();
        }
        if ((whiteListCount + count) > WL_SUPPLY) {
            revert MaxSupply();
        }
        if ((currentTokenId + count) > TOTAL_SUPPLY) {
            revert MaxSupply();
        }

        uint256[] memory tokens = new uint256[](count);
        for (uint16 i = 0; i < count; i++) {
            tokens[i] = ++currentTokenId;
            ++whiteListCount;
            _safeMint(recipient, tokens[i]);
        }
        return tokens; 
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

    /*
     * Owner methods to control contract settings and withdraw funds
     */

    function setAllowWhitelistMint(bool _allow) external onlyOwner {
        allowWhiteListMint = _allow;
    }

    function setAllowGeneralMint(bool _allow) external onlyOwner {
        allowGeneralMint = _allow;
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

    function supportsInterface(bytes4 interfaceId) public view virtual override (ERC721, ERC2981) returns (bool result) {
        /// @solidity memory-safe-assembly
        assembly {
            let s := shr(224, interfaceId)
            // ERC165: 0x01ffc9a7, ERC721: 0x80ac58cd, ERC721Metadata: 0x5b5e139f.
            // ERC2981: 0x2a55205a.
            result := or(or(or(eq(s, 0x01ffc9a7), eq(s, 0x80ac58cd)), eq(s, 0x2a55205a)), eq(s, 0x5b5e139f))
        }
    }

    function verifyAddress(address recipient, bytes32[] calldata _merkleProof) private view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(recipient));
        return MerkleProofLib.verify(_merkleProof, merkleRoot, leaf);
    }
}
