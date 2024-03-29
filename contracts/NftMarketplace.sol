// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

error NftMarketplace__PriceMustBeAboveZero();
error NftMarketplace__NotApprovedForMarketplace();
error NftMarketplace__AlreadyListed(address nftAddress, uint256 tokenId);
error NftMarketplace__NotOwner();
error NftMarketplace__NotListed(address nftAddress, uint256 tokenId);
error NftMarketplace__PriceNotMet(
    address nftAddress,
    uint256 tokenId,
    uint256 price
);
error NftMarketplace__NoProceeds();
error NftMarketplace__WithdrawFailed();

contract NftMarketplace is ReentrancyGuard {
    //Type Declarations
    struct Listing {
        uint256 price;
        address seller;
    }

    //storage variables
    //NFT contract address ->  NFT TokenId -> Listing
    mapping(address => mapping(uint256 => Listing)) private s_listings;

    // Create an array of listing instead?
    // Get all the NFTs a user owns?
    // Query some other weird data?
    // What if an array will be VERY gas expensive!!

    //we don't want to much change our protocol for just our website.

    //Seller address -> Amount Earned
    mapping(address => uint256) private s_proceeds;

    //events
    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event ItemCancelled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );
    ///////////////////////
    //     Modifiers     //
    //////////////////////

    modifier notListed(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0) {
            revert NftMarketplace__AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (owner != spender) {
            revert NftMarketplace__NotOwner();
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NftMarketplace__NotListed(nftAddress, tokenId);
        }
        _;
    }

    ///////////////////////
    //  Main Functions  //
    //////////////////////

    constructor(){
        console.log("NftMarketplace constructor");
    }

    /*
     * @notice Method for listing NFT
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param price sale price for each item
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    )
        external
        //Challenge: Have this contract accept payment in a subset of tokens as well.
        //Hint: Chainlink PriceFeeds converts the price of the tokens between each other.
        notListed(nftAddress, tokenId, msg.sender)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        if (price <= 0) {
            revert NftMarketplace__PriceMustBeAboveZero();
        }

        //1. Send the NFT to the contract. Transfer -> Contract "holds" the NFT.  --> Very Intrusive
        //2. Owner can still hold their NFT, and give the marketplace approval to sell the NFT for them.

        //IERC721 is just a interface for ERC721 tokens.
        IERC721 nft = IERC721(nftAddress);

        if (nft.getApproved(tokenId) != address(this)) {
            //this function returns the address of the approved accounts.
            revert NftMarketplace__NotApprovedForMarketplace();

            /*
             basically we store the tokenId to address mapping 
             // Mapping from token ID to approved address
             mapping(uint256 => address) private _tokenApprovals;
            */
        }
        //whenever updating a mapping, we must emit an event --> helpful in updating the frontend.
        s_listings[nftAddress][tokenId] = Listing(price, msg.sender);
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
    }

    //two things uniquely identifies a token --> nftAddress (contract address) and tokenId
    function buyItem(address nftAddress, uint256 tokenId)
        external
        payable
        nonReentrant
        isListed(nftAddress, tokenId)
    {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        if (msg.value < listedItem.price) {
            revert NftMarketplace__PriceNotMet(
                nftAddress,
                tokenId,
                listedItem.price
            );
        }
        //we  don't just send seller the money..?
        //Pull Over Push
        //Shift the risk associated with transferring ether to the user.

        //sending the money to the seller. ❌
        //have them withdraw the money. ✅

        s_proceeds[listedItem.seller] += msg.value;
        delete (s_listings[nftAddress][tokenId]);

        //transfering the ownership of the token.
        IERC721(nftAddress).safeTransferFrom(
            listedItem.seller,
            msg.sender,
            tokenId
        );
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
    }

    function cancelListing(address nftAddress, uint256 tokenId)
        external
        isOwner(nftAddress, tokenId, msg.sender)
        isListed(nftAddress, tokenId)
    {
        delete (s_listings[nftAddress][tokenId]);
        emit ItemCancelled(msg.sender, nftAddress, tokenId);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    )
        external
        isListed(nftAddress, tokenId)
        isOwner(nftAddress, tokenId, msg.sender)
    {
        s_listings[nftAddress][tokenId].price = newPrice;
        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
    }

    function withdrawProceeds() external payable nonReentrant{
        uint256 proceeds = s_proceeds[msg.sender];
        if(proceeds <= 0){
            revert NftMarketplace__NoProceeds();
        }
        s_proceeds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: proceeds}("");
        if(!success){
            revert NftMarketplace__WithdrawFailed();
        }
    }

    ///////////////////////////////
    //     Getter Functions      //
    ///////////////////////////////

    function getListing(address nftAddress, uint256 tokenId)
        external
        view
        returns (Listing memory listing)
    {
        return s_listings[nftAddress][tokenId];
    }

    function getProceeds(address seller)
        external
        view
        returns (uint256)
    {
        return s_proceeds[seller];
    }


}

/*
1. Create a decentralized NFT Marketplace
    1. `listItem`: List NFTs on the marketplace ✅
    2. `buyItem`: Buy the NFTs✅ 
    3. `cancelItem`: Cancel a listing ✅
    4. `updateListing`: Update Price ✅
    5. `withdrawProceeds`: Withdraw payment for my bought NFTs ✅
*/
