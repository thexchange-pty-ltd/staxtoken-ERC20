// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract StaxToken is ERC20, Ownable {
    uint256 public constant maxSupply = 1_000_000_000;
    uint256 public usdtPrice = 0.075 * 10**6;
    uint256 public privateListingEndTime;
    address[] public vestingGroups;
    IERC20 internal constant shibToken =
        IERC20(0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE);

    // Chainlink Price Feed Addresses
    AggregatorV3Interface internal immutable shibEthPriceFeed;
    AggregatorV3Interface internal immutable ethUsdtPriceFeed;

    constructor() ERC20("STAX Token", "STAX") Ownable(msg.sender) {
        // ETH/SHIB price feed address
        shibEthPriceFeed = AggregatorV3Interface(
            0x8dD1CD88F43aF196ae478e91b9F5E4Ac69A97C61
        );

        // ETH/USDT price feed address
        ethUsdtPriceFeed = AggregatorV3Interface(
            0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46
        );
        address[] memory addresses = new address[](0);

        uint256[] memory maxAmounts = new uint256[](0);
        // private round group
        addGroup(addresses, maxAmounts, VestingContract.VestingType.PRIVATE_ROUND);
    }

    function mint(uint256 amount) public payable mintingIsAllowed {
        uint256 totalPrice = convertUsdtToEth(
            (amount * usdtPrice) / (10**decimals())
        );
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        require(msg.value >= totalPrice, "Insufficient payment");
        // Refund excess ETH
        if (msg.value > totalPrice) {
            uint256 excessAmount = msg.value - totalPrice;
            payable(msg.sender).transfer(excessAmount);
        }
        address privateRoundAddress = vestingGroups[0];
        VestingContract privateRoundContract = VestingContract(
            privateRoundAddress
        );
        _mint(privateRoundAddress, amount);
        privateRoundContract.addShareholder(msg.sender, amount);
    }

    function mintForShib(uint256 amount) public mintingIsAllowed {
        uint256 totalPriceInShib = convertUsdtToShib(
            ((amount * usdtPrice) / (10**decimals()))
        );
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );

        shibToken.transferFrom(msg.sender, address(this), totalPriceInShib);

        address privateRoundAddress = vestingGroups[0];
        VestingContract privateRoundContract = VestingContract(
            privateRoundAddress
        );
        _mint(privateRoundAddress, amount);
        privateRoundContract.addShareholder(msg.sender, amount);
    }

    modifier mintingIsAllowed() {
        require(privateListingEndTime == 0, "Minting is finished");
        _;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function changePrice(uint256 _price) public onlyOwner {
        usdtPrice = _price;
    }

    // Function to withdraw collected ETH to the owner's wallet
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Transfer failed");
    }

    function withdrawShib() public onlyOwner {
        uint256 contractBalance = shibToken.balanceOf(address(this)); // Get SHIB balance of the contract
        require(contractBalance > 0, "No SHIB tokens in the contract");

        bool success = shibToken.transfer(owner(), contractBalance); // Transfer all SHIB tokens to the owner
        require(success, "SHIB transfer failed");
    }

    function airdrop(address to, uint256 amount) public onlyOwner {
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        _mint(to, amount);
       
    }

    function endPrivateListing(address treasuryVestingGroup, address account)
        public
        onlyOwner
    {
        privateListingEndTime = block.timestamp;
        uint256 maximumSupply = maxSupply * 10**decimals();
        if (totalSupply() < maximumSupply) {
            uint256 unmintedTokens = maximumSupply - totalSupply();
            addShareholder(treasuryVestingGroup, account, unmintedTokens);
        }
    }

    function addGroup(
        address[] memory shareholderAddresses,
        uint256[] memory shareholderMaxAmount,
        VestingContract.VestingType vestingType
    ) public onlyOwner {
        require(shareholderAddresses.length == shareholderMaxAmount.length, "Arrays must be the same length");
        uint256 amount = 0;
        for (uint256 i = 0; i < shareholderMaxAmount.length; i++)
            amount += shareholderMaxAmount[i];

        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        VestingContract vestingContract = new VestingContract(address(this), vestingType);
        _mint(address(vestingContract), amount);
        vestingGroups.push(address(vestingContract));
        
        // Add shareholders to the vesting contract
        for (uint256 i = 0; i < shareholderAddresses.length; i++) {
            vestingContract.addShareholder(shareholderAddresses[i], shareholderMaxAmount[i]);
        }
    }

    function addShareholder(
        address vestingGroupAddress,
        address account,
        uint256 amount
    ) public onlyOwner {
        require(
            totalSupply() + amount <= maxSupply * 10**decimals(),
            "Max supply exceeded"
        );
        
        // Verify this address is actually one of our vesting groups
        bool isValidVestingGroup = false;
        for (uint256 i = 0; i < vestingGroups.length; i++) {
            if (vestingGroups[i] == vestingGroupAddress) {
                isValidVestingGroup = true;
                break;
            }
        }
        require(isValidVestingGroup, "Address is not a valid vesting group");
        
        VestingContract vestingContract = VestingContract(vestingGroupAddress);
        _mint(vestingGroupAddress, amount);
        vestingContract.addShareholder(account, amount);
    }

    

    function getShibPriceInEth() public view returns (uint256) {
        (, int256 price, , , ) = shibEthPriceFeed.latestRoundData();

        return uint256(price);
    }

    function getEthPriceInUSDT() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdtPriceFeed.latestRoundData();

        return uint256(price);
    }

    function convertUsdtToShib(uint256 usdtAmount)
        public
        view
        returns (uint256)
    {
        uint256 ethPerShib = getShibPriceInEth();
        uint256 ethAmount = convertUsdtToEth(usdtAmount);
        uint256 shibAmount = (ethAmount / ethPerShib) * 10**18;

        return shibAmount;
    }

    function convertUsdtToEth(uint256 usdtAmount)
        public
        view
        returns (uint256)
    {
        uint256 usdtPerEth = getEthPriceInUSDT();

        uint256 ethAmount = (usdtAmount * usdtPerEth) / 10**6;

        return ethAmount;
    }
}

contract VestingContract is Ownable {
    uint256 public constant ONE_MONTH = 30 days;
    //uint256 public constant ONE_MONTH = 60;
    uint256 public constant TOTAL_PERCENTAGE = 10000;
    address public immutable staxTokenAddress;
    VestingType public immutable vestingType;

    enum VestingType {
        SEED_ROUND,           // 2.5% at 30d, 5% at 60d, 10% at 90d, then 10% monthly
        PRIVATE_ROUND,        // Same as seed round
        PUBLIC_LISTING,       // 10% immediate, then 10% monthly
        LIQUIDITY,           // 100% immediate
        MARKETING,           // 25% immediate, 25% at 30d, 25% at 60d, 25% at 90d
        REWARDS,             // Same as seed round
        REFERRALS_STAKING,   // Same as seed round
        ADVISORS,            // Same as seed round
        TEAM,                // Same as seed round
        TREASURY,            // 180d lock, then 10% monthly
        RESERVES,            // 10% immediate, then 10% monthly
        FOUNDERS             // 90d lock, then 10% monthly
    }

    struct ShareholderInfo {
        uint256 maximumTokens;
        uint256 withdrawnTokens;
    }

    mapping(address => ShareholderInfo) public shareholders;

    constructor(address _staxTokenAddress, VestingType _vestingType) Ownable(msg.sender) {
        staxTokenAddress = _staxTokenAddress;
        vestingType = _vestingType;
    }

    function calculateAllowedAmount(address shareholderAddress)
        public
        view
        returns (uint256)
    {
        ShareholderInfo memory shareholder = shareholders[shareholderAddress];
        if (shareholder.maximumTokens == 0) return 0;

        StaxToken staxToken = StaxToken(staxTokenAddress);
        uint256 listingTime = staxToken.privateListingEndTime();
        
        if (listingTime == 0) return 0; // Listing hasn't started yet

        uint256 timeSinceListing = block.timestamp - listingTime;
        uint256 allowedPercentage = calculateVestingPercentage(
            vestingType,
            timeSinceListing
        );

        uint256 allowedAmount = (shareholder.maximumTokens * allowedPercentage) / TOTAL_PERCENTAGE;
        return allowedAmount;
    }

    function calculateVestingPercentage(VestingType _vestingType, uint256 timeSinceListing)
        public
        pure
        returns (uint256)
    {
        uint256 months = timeSinceListing / ONE_MONTH;
        
        if (_vestingType == VestingType.LIQUIDITY) {
            return TOTAL_PERCENTAGE; // 100% immediate
        }
        
        if (_vestingType == VestingType.PUBLIC_LISTING || _vestingType == VestingType.RESERVES) {
            // 10% immediate, then 10% monthly
            uint256 publicReservesPercentage = 1000 + (months * 1000); // 10% + (months * 10%)
            return publicReservesPercentage > TOTAL_PERCENTAGE ? TOTAL_PERCENTAGE : publicReservesPercentage;
        }
        
        if (_vestingType == VestingType.MARKETING) {
            // 25% immediate, 25% at 30d, 25% at 60d, 25% at 90d
            uint256 marketingPercentage = (months + 1) * 2500; // (months + 1) * 25%
            return marketingPercentage > TOTAL_PERCENTAGE ? TOTAL_PERCENTAGE : marketingPercentage;
        }
        
        if (_vestingType == VestingType.TREASURY) {
            // 6 months lock, then 10% monthly
            if (timeSinceListing < 6 * ONE_MONTH) return 0;
            uint256 monthsAfterLock = (timeSinceListing - 6 * ONE_MONTH) / ONE_MONTH;
            uint256 treasuryPercentage = (monthsAfterLock + 1) * 1000; // (months + 1) * 10%
            return treasuryPercentage > TOTAL_PERCENTAGE ? TOTAL_PERCENTAGE : treasuryPercentage;
        }
        
        if (_vestingType == VestingType.FOUNDERS) {
            // 3 months lock, then 10% monthly
            if (timeSinceListing < 3 * ONE_MONTH) return 0;
            uint256 monthsAfterLock = (timeSinceListing - 3 * ONE_MONTH) / ONE_MONTH;
            uint256 foundersPercentage = (monthsAfterLock + 1) * 1000; // (months + 1) * 10%
            return foundersPercentage > TOTAL_PERCENTAGE ? TOTAL_PERCENTAGE : foundersPercentage;
        }
        
        // Default for SEED_ROUND, PRIVATE_ROUND, REWARDS, REFERRALS_STAKING, ADVISORS, TEAM
        // 2.5% at 30d, 5% at 60d, 10% at 90d, then 10% monthly
        if (months == 0) return 0; // No tokens before 30 days
        if (months == 1) return 250; // 2.5%
        if (months == 2) return 750; // 2.5% + 5% = 7.5%
        if (months == 3) return 1750; // 2.5% + 5% + 10% = 17.5%
        
        // After 90 days: 17.5% + (additional months * 10%)
        uint256 additionalMonths = months - 3;
        uint256 totalPercentage = 1750 + (additionalMonths * 1000); // 17.5% + (additional months * 10%)
        return totalPercentage > TOTAL_PERCENTAGE ? TOTAL_PERCENTAGE : totalPercentage;
    }

    function withdraw() public onlyShareholder {
        uint256 allowedAmount = calculateAllowedAmount(msg.sender);
        uint256 withdrawnTokens = shareholders[msg.sender].withdrawnTokens;
        require(allowedAmount > withdrawnTokens, "No tokens available for withdrawal");
        
        StaxToken staxToken = StaxToken(staxTokenAddress);
        uint256 amount = allowedAmount - withdrawnTokens;
        require(amount > 0, "No tokens available for withdrawal");
        staxToken.transfer(msg.sender, amount);
        shareholders[msg.sender].withdrawnTokens += amount;
    }

    function addShareholder(
        address account, 
        uint256 maximumTokens
    ) public onlyOwner {
        if (shareholders[account].maximumTokens > 0) {
            shareholders[account].maximumTokens += maximumTokens;
        } else {
            shareholders[account] = ShareholderInfo(maximumTokens, 0);
        }
    }

    function getVestingInfo(address shareholderAddress) 
        public 
        view 
        returns (
            uint256 maximumTokens,
            uint256 withdrawnTokens,
            VestingType contractVestingType,
            uint256 availableForWithdrawal
        ) 
    {
        ShareholderInfo memory shareholder = shareholders[shareholderAddress];
        maximumTokens = shareholder.maximumTokens;
        withdrawnTokens = shareholder.withdrawnTokens;
        contractVestingType = vestingType;
        availableForWithdrawal = calculateAllowedAmount(shareholderAddress) - withdrawnTokens;
    }

    modifier onlyShareholder() {
        require(
            shareholders[msg.sender].maximumTokens > 0,
            "Only shareholder can call"
        );
        _;
    }
}
