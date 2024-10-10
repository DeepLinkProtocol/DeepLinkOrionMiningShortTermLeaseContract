// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract DLCNode is Initializable, ERC721Upgradeable, OwnableUpgradeable {
    uint256 private _nextTokenId;
    uint256 private TOKEN_CAP;

    struct TokenIdRange {
        uint256 startTokenId;
        uint256 endTokenId;
        uint256 nextTokenId;
    }

    mapping(uint16 => TokenIdRange) public levelNumber2TokenIdRange;

    event mintedToken(address indexed to, uint256 startTokenId, uint256 endTokenId);

    function initialize(address initialOwner) public initializer {
        __ERC721_init("DLC-Node", "DLCN");
        __Ownable_init(initialOwner);
        TOKEN_CAP = 120_000;
        setLevel2TokenIdRange();
    }

    function setLevel2TokenIdRange() internal onlyOwner {
        levelNumber2TokenIdRange[1] = TokenIdRange(1, 8000, 1);
        levelNumber2TokenIdRange[2] = TokenIdRange(8001, 18000, 8001);
        levelNumber2TokenIdRange[3] = TokenIdRange(18001, 30000, 18001);
        levelNumber2TokenIdRange[4] = TokenIdRange(30001, 45000, 30001);
        levelNumber2TokenIdRange[5] = TokenIdRange(45001, 66000, 45001);
        levelNumber2TokenIdRange[6] = TokenIdRange(66001, 82000, 66001);
        levelNumber2TokenIdRange[7] = TokenIdRange(82001, 94000, 82001);
        levelNumber2TokenIdRange[8] = TokenIdRange(94001, 104000, 94001);
        levelNumber2TokenIdRange[9] = TokenIdRange(104001, 112000, 104001);
        levelNumber2TokenIdRange[10] = TokenIdRange(112001, 120000, 112001);
    }

    function safeBatchMint(address to, uint16 level, uint256 amount) public onlyOwner {
        require(level <= 10 && level >= 1, "Level should be between 1 and 10");
        TokenIdRange memory levelTokenIdRange = levelNumber2TokenIdRange[level];
        require(levelTokenIdRange.nextTokenId - 1 + amount <= levelTokenIdRange.endTokenId, "Token range not available");

        uint256 startTokenId = levelTokenIdRange.nextTokenId;
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = levelTokenIdRange.nextTokenId++;
            _safeMint(to, tokenId);
        }
        levelNumber2TokenIdRange[level] = levelTokenIdRange;
        uint256 endTokenId = levelTokenIdRange.nextTokenId - 1;
        emit mintedToken(to, startTokenId, endTokenId);
    }

    function _baseURI() internal pure override returns (string memory) {
        return
        "https://raw.githubusercontent.com/DeepLinkProtocol/DeepLinkNodeNFTContact/master/resource/DLC-node-metadata/";
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        uint16 levelNumber = 1;
        for (uint16 level = 1; level <= 10; level++) {
            TokenIdRange memory levelTokenIdRange = levelNumber2TokenIdRange[level];
            if (levelTokenIdRange.startTokenId <= tokenId && tokenId <= levelTokenIdRange.endTokenId) {
                levelNumber = level;
                break;
            }
        }

        return string(abi.encodePacked(_baseURI(), Strings.toString(levelNumber), ".json"));
    }

    function version() public pure returns (uint256) {
        return 0;
    }
}
