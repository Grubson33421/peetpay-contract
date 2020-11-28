pragma solidity >=0.6.0;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import "./IERC20.sol";

contract PeetPay {
    struct BonusFloor {
        uint256 from;
        uint256 to;
        uint256 bonus;
    }

    IUniswapV2Router02 public uniswapRouter;

    address
        internal constant UNISWAP_ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address
        internal constant pteTokenAddress = 0x2158146E3012f671e4E3EEE72611224027c3FcFD;
    address
        internal constant wethTokenAddress = 0xc778417E063141139Fce010982780140Aa0cD5Ab;

    address private owner;
    BonusFloor[] private bonusFloors;
    uint256 private currentPTESolded = 0;
    bool private isBonusApplied = true;
    uint256 private minPricePTE = 0;

    event PriceEstimated(
        address indexed _from,
        uint256 deposit,
        uint256 _value,
        uint256 currentBonus
    );
    event Received(address, uint);

     event BonusStateChange(
        address indexed _from,
        bool enabled
    );

    constructor() public {
        owner = msg.sender;
        uniswapRouter = IUniswapV2Router02(UNISWAP_ROUTER_ADDRESS);

        // Init bonus floors
        uint256 unitPte = 1000000000000000000;
        minPricePTE = unitPte * 40;
        bonusFloors.push(BonusFloor(0, unitPte * 50, 5));
        bonusFloors.push(BonusFloor(unitPte * 50, unitPte * 100, 4));
        bonusFloors.push(BonusFloor(unitPte * 100, unitPte * 200, 3));
        bonusFloors.push(BonusFloor(unitPte * 200, unitPte * 1000, 2));
        bonusFloors.push(BonusFloor(unitPte * 1000, unitPte * 2000, 1));
        bonusFloors.push(BonusFloor(unitPte * 2000, unitPte * 100000, 0));
    }

    function setMinPricePTE(uint256 price) public payable {
        require(msg.sender == owner, "Only the owner can do that");
        minPricePTE = price;
    }

    function withdraw(address withdrawWallet) public payable {
        require(msg.sender == owner, "Only the owner can do that");
        IERC20 wethToken = IERC20(wethTokenAddress);
        IERC20 pteToken = IERC20(pteTokenAddress);

        // Transfert token to the specified wallet
        wethToken.transfer(withdrawWallet, wethToken.balanceOf(address(this)));
        pteToken.transfer(withdrawWallet, pteToken.balanceOf(address(this)));
        msg.sender.transfer(this.balance);
    }

    function withdrawSpecificToken(address withdrawWallet, address tokenAddr)
        public
        payable
    {
        require(msg.sender == owner, "Only the owner can do that");
        IERC20 token = IERC20(tokenAddr);

        // Transfert token to the specified wallet
        token.transfer(withdrawWallet, token.balanceOf(address(this)));
    }

    function setBonusSystemState(bool enable) public payable {
        require(msg.sender == owner, "Only the owner can do that");
        isBonusApplied = enable;
        emit BonusStateChange(msg.sender, isBonusApplied);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
        transfertPTE(msg.value);
    }

    function getPtePriceForETH(uint256 _amount) private returns (uint256 pteEstimated, uint256 pteForOneUnitEstimated) {
        // Transfer PTE to the sender
        (uint256 reserveWETH, uint256 reservePTE) = UniswapV2Library
            .getReserves(
            uniswapRouter.factory(),
            wethTokenAddress,
            pteTokenAddress
        );
        uint256 _pteEstimated = uniswapRouter.quote(
            _amount,
            reserveWETH,
            reservePTE
        );
        uint256 _pteForOneUnitEstimated = uniswapRouter.quote(
            1000000000000000000,
            reserveWETH,
            reservePTE
        );
        return (_pteEstimated, _pteForOneUnitEstimated);
    }

    function transfertPTE(uint256 _srcAmount) private {
        (uint256 pteEstimated, uint256 pteForOneUnitEstimated) = getPtePriceForETH(_srcAmount);
        require(
            pteForOneUnitEstimated >= minPricePTE,
            "PTE price too low"
        );
        IERC20 pteToken = IERC20(pteTokenAddress);
        uint256 currentBonus = getCurrentSaleBonus();
        uint256 pteAmount = pteEstimated + ((currentBonus / 100) * pteEstimated);
        emit PriceEstimated(msg.sender, _srcAmount, pteAmount, currentBonus);
        require(
            pteToken.balanceOf(address(this)) >= pteAmount,
            "No PTE amount required on the contract"
        );
        currentPTESolded += pteAmount;
        pteToken.transfer(msg.sender, pteAmount);
    }

    function transferToken(uint256 _amount) public payable {
        IERC20 token = IERC20(wethTokenAddress);

        // Remove wether from the sender
        require(
            _amount > 0,
            "Invalid amount"
        );
        require(
            token.balanceOf(msg.sender) >= _amount,
            "No WETH amount required"
        );
        require(
            token.transferFrom(msg.sender, address(this), _amount) == true,
            "Can't transfert WETH on the contract"
        );

        transfertPTE(_amount);
    }

    function getCurrentSoldedPTEAmount() public view returns (uint amount) {
        return currentPTESolded;
    }

    function getCurrentSaleBonus() public view returns (uint256 bonusPercent) {
        if(!isBonusApplied) {
            return 0;
        }
        for (uint256 i = 0; i < bonusFloors.length; i++) {
            BonusFloor memory floor = bonusFloors[i];
            if (currentPTESolded >= floor.from && currentPTESolded < floor.to) {
                return floor.bonus;
            }
        }
        return 0;
    }
}
