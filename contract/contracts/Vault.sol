// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./interfaces/IDacadePunks.sol";
import "./interfaces/IDacadePunksToken.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Vault is Ownable, IERC721Receiver {
    uint256 public totalItemsStaked;
    uint256 private constant MONTH = 30 days;

    IDacadePunks immutable nft;
    IDacadePunksToken immutable token;

    struct Stake {
        address owner;
        uint256 stakedAt;
    }

    mapping(uint256 => Stake) vault;

    event ItemsStaked(uint256[] tokenId, address owner);
    event ItemsUnstaked(uint256[] tokenIds, address owner);
    event Claimed(address owner, uint256 reward);

    error NFTStakingVault__ItemAlreadyStaked();
    error NFTStakingVault__NotItemOwner();

    constructor(address _nftAddress, address _tokenAddress) {
        nft = IDacadePunks(_nftAddress);
        token = IDacadePunksToken(_tokenAddress);
    }

    function stake(uint256[] calldata tokenIds) external {
        uint256 tokenId;
        uint256 stakedCount;
        uint256 len = tokenIds.length;

        for (uint256 i; i < len; ) {
            tokenId = tokenIds[i];
            if (vault[tokenId].owner != address(0)) {
                revert NFTStakingVault__ItemAlreadyStaked();
            }
            if (nft.ownerOf(tokenId) != msg.sender) {
                revert NFTStakingVault__NotItemOwner();
            }

            nft.safeTransferFrom(msg.sender, address(this), tokenId);
            vault[tokenId] = Stake(msg.sender, block.timestamp);

            unchecked {
                stakedCount++;
                ++i;
            }
        }
        totalItemsStaked = totalItemsStaked + stakedCount;

        emit ItemsStaked(tokenIds, msg.sender);
    }

    function unstake(uint256[] calldata tokenIds) external {
        _claim(msg.sender, tokenIds, true);
    }

    function claim(uint256[] calldata tokenIds) external {
        _claim(msg.sender, tokenIds, false);
    }

    function _claim(
        address user,
        uint256[] calldata tokenIds,
        bool unstakeAll
    ) internal {
        uint256 tokenId;
        uint256 rewardEarned;
        uint256 len = tokenIds.length;

        for (uint256 i; i < len; ) {
            tokenId = tokenIds[i];
            if (vault[tokenId].owner != user) {
                revert NFTStakingVault__NotItemOwner();
            }
            uint256 _stakedAt = vault[tokenId].stakedAt;

            uint256 stakingPeriod = block.timestamp - _stakedAt;
            uint256 _dailyReward = _calculateReward(stakingPeriod);
            rewardEarned += (_dailyReward * stakingPeriod * 1e18) / 1 days;

            vault[tokenId].stakedAt = block.timestamp;

            unchecked {
                ++i;
            }
        }

        emit Claimed(user, rewardEarned);

        if (rewardEarned != 0) {
            token.mint(user, rewardEarned);
        }

        if (unstakeAll) {
            _unstake(user, tokenIds);
        }
    }

    function _unstake(address user, uint256[] calldata tokenIds) internal {
        uint256 tokenId;
        uint256 unstakedCount;

        uint256 len = tokenIds.length;
        for (uint256 i; i < len; ) {
            tokenId = tokenIds[i];
            require(vault[tokenId].owner == user, "Not Owner");

            nft.safeTransferFrom(address(this), user, tokenId);
            delete vault[tokenId];

            unchecked {
                unstakedCount++;
                ++i;
            }
        }
        totalItemsStaked = totalItemsStaked - unstakedCount;

        // emit final event after for loop to save gas
        emit ItemsUnstaked(tokenIds, user);
    }

    function _calculateReward(
        uint256 stakingPeriod
    ) internal pure returns (uint256 dailyReward) {
        if (stakingPeriod <= MONTH) {
            dailyReward = 1;
        } else if (stakingPeriod < 3 * MONTH) {
            dailyReward = 2;
        } else if (stakingPeriod < 6 * MONTH) {
            dailyReward = 4;
        } else if (stakingPeriod >= 6 * MONTH) {
            dailyReward = 8;
        }
    }

    function getDailyReward(
        uint256 stakingPeriod
    ) external pure returns (uint256 dailyReward) {
        dailyReward = _calculateReward(stakingPeriod);
    }

    function getTotalRewardEarned(
        address user
    ) external view returns (uint256 rewardEarned) {
        uint256[] memory tokens = tokensOfOwner(user);

        uint256 len = tokens.length;
        for (uint256 i; i < len; ) {
            uint256 _stakedAt = vault[tokens[i]].stakedAt;
            uint256 stakingPeriod = block.timestamp - _stakedAt;
            uint256 _dailyReward = _calculateReward(stakingPeriod);
            rewardEarned += (_dailyReward * stakingPeriod * 1e18) / 1 days;
            unchecked {
                ++i;
            }
        }
    }

    function getRewardEarnedPerNft(
        uint256 _tokenId
    ) external view returns (uint256 rewardEarned) {
        uint256 _stakedAt = vault[_tokenId].stakedAt;
        uint256 stakingPeriod = block.timestamp - _stakedAt;
        uint256 _dailyReward = _calculateReward(stakingPeriod);
        rewardEarned = (_dailyReward * stakingPeriod * 1e18) / 1 days;
    }

    function balanceOf(
        address user
    ) public view returns (uint256 nftStakedbalance) {
        uint256 supply = nft.totalSupply();
        unchecked {
            for (uint256 i; i <= supply; ++i) {
                if (vault[i].owner == user) {
                    nftStakedbalance += 1;
                }
            }
        }
    }

    function tokensOfOwner(
        address user
    ) public view returns (uint256[] memory tokens) {
        uint256 balance = balanceOf(user);
        uint256 supply = nft.totalSupply();
        tokens = new uint256[](balance);

        uint256 counter;

        if (balance == 0) {
            return tokens;
        }

        unchecked {
            for (uint256 i; i <= supply; ++i) {
                if (vault[i].owner == user) {
                    tokens[counter] = i;
                    counter++;
                }
                if (counter == balance) {
                    return tokens;
                }
            }
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}