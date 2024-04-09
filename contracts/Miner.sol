// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./Bank.sol";

contract Miner {
    address public owner;

    uint256 public apy;

    address private bank;

    uint256 public transaction_fee;

    uint256 public referral_fee;

    uint256 public penalty_fee;

    uint256 public minDuration;

    uint256 public minDeposit = 0.01 ether;

    address private transactionFeeWallet;

    address private penaltyFeeWallet;

    struct User {
        address user;
        uint256 amount;
        uint256 roi;
        address referee;
        address[] referrals;
        uint256 referralBalance;
        uint256 lastDeposited;
        uint256 lastClaimed;
        bool claimed;
    }

    User[] public users;

    mapping (address => User) public user;

    event User_Created(address indexed user);

    event Mine(address indexed user, uint256 amount);

    event ReMine(address indexed user, uint256 amount);

    event Claim(address indexed user, uint256 amount);

    event Withdraw(address indexed user, uint256 amount);

    constructor(uint256 _apy, uint256 tFee, uint256 rFee, uint256 pFee, uint256 _duration, address _bank, address wallet1, address wallet2) {
        owner = msg.sender;

        apy = _apy;

        require(tFee <= 5, "Transaction fee cannot exceed 5%");

        require(rFee <= 5, "Referral fee cannot exceed 5%");

        require(pFee <= 50, "Penalty fee cannot exceed 50%");

        transaction_fee = (tFee  * 1 ether) / 1000;

        referral_fee = rFee;

        penalty_fee = pFee;

        minDuration = _duration * 86400;

        bank = _bank;

        transactionFeeWallet = wallet1;

        penaltyFeeWallet = wallet2;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function changeAPY(uint256 _apy) public onlyOwner {
        apy = _apy;
    }

    function changeTransactionFee(uint256 tFee) public onlyOwner {
        require(tFee <= 5, "Transaction fee cannot exceed 5%");

        transaction_fee = (tFee / 1000) * 1 ether;
    }

    function changeReferralFee(uint256 rFee) public onlyOwner {
        require(rFee <= 5, "Referral fee cannot exceed 5%");

        referral_fee = rFee;
    }

    function changePenaltyFee(uint256 pFee) public onlyOwner {
        require(pFee <= 50, "Penalty fee cannot exceed 50%");
        
        penalty_fee = pFee;
    }

    function changeMinDeposit(uint256 _deposit) public onlyOwner {
        minDeposit = _deposit;
    }

    function changeMinDuration(uint256 _duration) public onlyOwner {
        minDuration = _duration * 86400;
    }

    function changeTFeeWallet(address tFeeWallet) public onlyOwner {
        transactionFeeWallet = tFeeWallet;
    }

    function changePFeeWallet(address pFeeWallet) public onlyOwner {
        penaltyFeeWallet = pFeeWallet;
    }

    function changeBank(address _bank) public onlyOwner {
        bank = _bank;
    }

    function userExists(address _user) internal view returns (bool) {
        bool user_exist = false;

        for(uint256 i = 0; i < users.length; i++) {
            if(users[i].user == _user) {
                user_exist = true;

                break;
            }
        }

        return user_exist;
    }

    function createUser(address user_, uint256 _amount, uint256 _roi, address _referee) internal {
        address[] memory _referrals;


        User memory _user = User({
            user: user_,
            amount: _amount,
            roi: _roi,
            referee: _referee,
            referrals: _referrals,
            referralBalance: 0,
            lastDeposited: block.timestamp,
            lastClaimed: 0,
            claimed: false
        });

        users.push(_user);

        user[user_] = _user;

        emit User_Created(user_);
    }

    function mine(address _referee) public payable {
        require(msg.value >= minDeposit + transaction_fee, "Insufficent deposit amount.");

        uint256 amount = msg.value - transaction_fee;

        if(userExists(msg.sender)) {
            User storage _user = user[msg.sender];
            uint256 total = amount + _user.amount;
            uint256 _roi = (apy * total) / 100;

            _user.amount = total;
            _user.roi = _roi;
            _user.lastDeposited = block.timestamp;
        } else {
            uint256 _roi = (apy * amount) / 100;

            createUser(msg.sender, amount, _roi, _referee);

            if(_referee != address(0)) {
                User storage referee = user[_referee];
                referee.referrals.push(msg.sender);
            }
        }

        (bool os, ) = payable(bank).call{value: amount}("");
        require(os, "Bank transfer failed.");

        (bool os1, ) = payable(transactionFeeWallet).call{value: transaction_fee}("");
        require(os1, "Transaction fee transfer failed.");

        emit Mine(msg.sender, amount);
    }

    function re_mine() public payable {
        require(msg.value >= transaction_fee, "Insufficent transaction fee amount.");

        require(userExists(msg.sender), "No user account detected.");

        User storage _user = user[msg.sender];
        uint256 duration;

        if(_user.lastDeposited >= _user.lastClaimed) {
            duration = block.timestamp - _user.lastDeposited;
        } else {
            duration = block.timestamp - _user.lastClaimed;
        }

        uint256 roi_mined;

        if(duration >= minDuration) {
            roi_mined = (_user.roi * minDuration) / (365 * 86400);
        } else {
            roi_mined = (_user.roi * duration) / (365 * 86400);
        }
        
        uint256 total = _user.amount + roi_mined;
        uint256 _roi = (apy * total) / 100;

        _user.amount = total;
        _user.roi = _roi;
        _user.lastDeposited = block.timestamp;

        (bool os, ) = payable(transactionFeeWallet).call{value: transaction_fee}("");
        require(os, "Transaction fee transfer failed.");

        emit ReMine(msg.sender, _user.roi);
    }

    function claimRewards() public payable {
        require(msg.value >= transaction_fee, "Insufficent transaction fee amount.");

        require(userExists(msg.sender), "No user account detected.");

        Bank _bank = Bank(payable(bank));

        User storage _user = user[msg.sender];
        
        uint256 duration;

        if(_user.lastDeposited >= _user.lastClaimed) {
            duration = block.timestamp - _user.lastDeposited;
        } else {
            duration = block.timestamp - _user.lastClaimed;
        }

        uint256 amount;

        if(duration >= minDuration) {
            uint256 rTax = 0;
            uint256 roi_mined = (_user.roi * minDuration) / (365 * 86400);

            if(_user.referee != address(0)) {
                rTax = (referral_fee * roi_mined) / 100;

                User storage referee = user[_user.referee];
                referee.referralBalance += rTax;
            }

            amount = roi_mined - rTax;
        } else {
            uint256 rTax = 0;
            uint256 roi_mined = (_user.roi * duration) / (365 * 86400);
            uint256 pTax = 0;

            if(_user.claimed) {
                pTax = (penalty_fee * roi_mined) / 100;
            }

            if(_user.referee != address(0)) {
                rTax = (referral_fee * roi_mined) / 100;

                User storage referee = user[_user.referee];
                referee.referralBalance += rTax;
            }

            amount = roi_mined - (rTax + pTax);

            _bank.transfer(penaltyFeeWallet, pTax);
        }

        _bank.transfer(msg.sender, amount);

        _user.lastClaimed = block.timestamp;

        _user.claimed = true;

        (bool os, ) = payable(transactionFeeWallet).call{value: transaction_fee}("");
        require(os, "Transaction fee transfer failed.");

        emit Claim(msg.sender, amount);
    }

    function withdraw() public payable {
        require(msg.value >= transaction_fee, "Insufficent transaction fee amount.");

        require(userExists(msg.sender), "No user account detected.");

        Bank _bank = Bank(payable(bank));

        User storage _user = user[msg.sender];
        
        uint256 duration;

        if(_user.lastDeposited >= _user.lastClaimed) {
            duration = block.timestamp - _user.lastDeposited;
        } else {
            duration = block.timestamp - _user.lastClaimed;
        }

        uint256 amount;

        if(duration >= minDuration) {
            uint256 rTax = 0;
            uint256 roi_mined = (_user.roi * minDuration) / (365 * 86400);

            if(_user.referee != address(0)) {
                rTax = (referral_fee * roi_mined) / 100;

                User storage referee = user[_user.referee];
                referee.referralBalance += rTax;
            }

            amount = (_user.amount + _user.referralBalance + roi_mined) - rTax;
        } else {
            uint256 rTax = 0;
            uint256 roi_mined = (_user.roi * duration) / (365 * 86400);
            uint256 pTax = (penalty_fee * (_user.amount + roi_mined)) / 100;

            if(_user.referee != address(0)) {
                rTax = (referral_fee * roi_mined) / 100;

                User storage referee = user[_user.referee];
                referee.referralBalance += rTax;
            }

            amount = (_user.amount + _user.referralBalance + roi_mined) - (rTax + pTax);

            _bank.transfer(penaltyFeeWallet, pTax);
        }

        _bank.transfer(msg.sender, amount);

        _user.amount = 0;

        _user.roi = 0;

        _user.referralBalance = 0;

        _user.lastClaimed = block.timestamp;

        (bool os, ) = payable(transactionFeeWallet).call{value: transaction_fee}("");
        require(os, "Transaction fee transfer failed.");

        emit Withdraw(msg.sender, amount);
    }
}