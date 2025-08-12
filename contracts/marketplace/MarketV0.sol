// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts@4.5.0/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/security/ReentrancyGuard.sol";

contract NFTMarketplace is Ownable, ReentrancyGuard {
    struct Listing {
        address seller;
        uint256 tokenId;
        uint256 price;
    }

    IERC20 public paymentToken; // ERC20 token used for purchases
    IERC721 public nftContract; // NFT contract set in constructor
    address public feeWallet; // Wallet to collect fees
    uint256 public feePercent = 200; // Default 2% fee (in basis points)

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => uint256) public tokenToListingId;
    uint256 private currentListingId;

    event Listed(
        uint256 listingId,
        address seller,
        uint256 tokenId,
        uint256 price,
        string uuid
    );
    event Purchased(
        uint256 listingId,
        address buyer,
        uint256 tokenId,
        uint256 price,
        string uuid
    );
    event Delisted(uint256 listingId, uint256 tokenId, string uuid);
    event PriceUpdated(
        uint256 listingId,
        uint256 newPrice,
        string uuid
    );

    constructor(
        address _paymentToken,
        address _nftContract,
        address _feeWallet
    ) {
        require(_paymentToken != address(0), "Invalid payment token address");
        require(_nftContract != address(0), "Invalid NFT contract address");
        require(_feeWallet != address(0), "Invalid fee wallet address");

        paymentToken = IERC20(_paymentToken);
        nftContract = IERC721(_nftContract);
        feeWallet = _feeWallet;
    }

    function listNFT(
        uint256 _tokenId,
        uint256 _price,
        string calldata uuid
    ) external nonReentrant {
        require(_price > 0, "Price must be greater than zero");
        require(
            nftContract.ownerOf(_tokenId) == msg.sender,
            "You must own the NFT"
        );
        require(tokenToListingId[_tokenId] == 0, "NFT is already listed"); // Check if already listed
        require(
            nftContract.getApproved(_tokenId) == address(this) ||
                nftContract.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved"
        );

        currentListingId++;
        listings[currentListingId] = Listing({
            seller: msg.sender,
            tokenId: _tokenId,
            price: _price
        });

        tokenToListingId[_tokenId] = currentListingId; // Mark NFT as listed

        emit Listed(currentListingId, msg.sender, _tokenId, _price, uuid);
    }

    function purchaseNFT(uint256 _listingId, string calldata uuid)
        external
        nonReentrant
    {
        Listing memory listing = listings[_listingId];
        require(listing.price > 0, "Listing does not exist");

        bool stillOwner = (nftContract.ownerOf(listing.tokenId) ==
            listing.seller);
        bool stillApproved = (nftContract.getApproved(listing.tokenId) ==
            address(this) ||
            nftContract.isApprovedForAll(listing.seller, address(this)));

        require(stillOwner, "Listing is invalid (NFT not owned anymore).");
        require(
            stillApproved,
            "Listing is invalid (Marketplace not approved anymore)."
        );

        uint256 feeAmount = (listing.price * feePercent) / 10000;
        uint256 sellerAmount = listing.price - feeAmount;

        require(
            paymentToken.transferFrom(msg.sender, feeWallet, feeAmount),
            "Fee payment failed"
        );
        require(
            paymentToken.transferFrom(msg.sender, listing.seller, sellerAmount),
            "Seller payment failed"
        );

        nftContract.safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        // Now it's safe to delete
        delete listings[_listingId];
        delete tokenToListingId[listing.tokenId];

        emit Purchased(
            _listingId,
            msg.sender,
            listing.tokenId,
            listing.price,
            uuid
        );
    }

    function updateListingPrice(
        uint256 _listingId,
        uint256 _newPrice,
        string calldata uuid
    ) external nonReentrant {
        require(_newPrice > 0, "Price must be greater than zero");
        Listing storage listing = listings[_listingId];
        require(listing.price > 0, "Listing does not exist");
        require(
            nftContract.ownerOf(listing.tokenId) == msg.sender,
            "You must be the NFT owner"
        );
        listing.price = _newPrice;

        emit PriceUpdated(_listingId,  _newPrice, uuid);
    }

    function delistNFT(uint256 _listingId, string calldata uuid) external {
        Listing memory listing = listings[_listingId];
        require(listing.seller == msg.sender, "Only seller can delist");

        delete listings[_listingId];
        delete tokenToListingId[listing.tokenId]; // Mark as not listed

        emit Delisted(_listingId, listing.tokenId, uuid);
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        require(_feeWallet != address(0), "Invalid fee wallet address");
        feeWallet = _feeWallet;
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 10000, "Fee must be <= 100%");
        feePercent = _feePercent;
    }

    function getListing(uint256 _listingId)
        external
        view
        returns (Listing memory)
    {
        return listings[_listingId];
    }
}
