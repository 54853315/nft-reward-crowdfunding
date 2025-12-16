// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
// import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
contract RewardNFT is ERC721, Ownable {
    string[3] baseURI = ["ipfs://bronze/", "ipfs://silver/", "ipfs://gold/"];
    uint256 private _nextTokenId;

    // 存储每个 tokenId 对应的 tier
    mapping(uint256 => uint256) private _tokenTiers;

    event NFTMinted(uint256 indexed tokenId, address indexed user1, uint256 timestamp);

    constructor() ERC721("CrowdBadge", "BADGE") Ownable(msg.sender) {}

    function mint(address to, uint tier) external onlyOwner returns (uint256) {
        require(to != address(0), "Invalid address");
        require(tier < 3, "Invalid tier");
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _tokenTiers[tokenId] = tier;
        emit NFTMinted(tokenId, to, block.timestamp);
        return tokenId;
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    function tokenURI(uint tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return string(abi.encodePacked(baseURI[_tokenTiers[tokenId]]));
    }

    function tierOf(uint256 tokenId) public view returns (uint256) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return _tokenTiers[tokenId];
    }
}
