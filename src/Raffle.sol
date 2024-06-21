// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations (Enum)
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A sample Raffle Contract
 * @author Patrick Collins
 * @notice This contract is for creating a simple raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle_UpKeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState // RaffleState can be converted to uint256
    );

    /**
     * Type Declarations
     */
    enum RaffleState {
        // in Solidity enums can be converted to uint
        OPEN, // 0
        CALCULATING // 1
    }

    /**
     * State Variables
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    // @dev Duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;

    address payable[] private s_players; // it's a storage variable because it is going to be changed
    // because we need to pay the players some ETH, the address should be payable
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /**
     * Events
     */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        // because we inherit from the contract VRFConsumerBaseV2 and it has a contructor that we have to mention
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_gasLane = gasLane;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // we want people to pay for a ticket to enter the raffle and we have to have a ticket price in ETH
        //require(msg.value >= i_entranceFee, "Not enough ETH sent!");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender)); // we need the payable keyword to make an address allowed to get ETH
        emit EnteredRaffle(msg.sender);
    }

    // upkeepNeeded is needed when the lottery is ready to pick a winner
    // bytes memory performData - if there's any additional data that needs to be passed to performUpkeep() function
    /**
     * @dev This is the function that the Chainlink Automation nodes call
     * to see if it's time to perform an upkeep (an action).
     * The following should be true for this to return true:
     * 1. The time interval has been passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription iis funded with LINK
     */
    function checkUpKeep(
        bytes memory /*checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /*performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 0x0 = blank bytes object

    // 1. Get a random number
    // 2. Use the random number to pick a player
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpKeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        // check if enough time has passed
        // 1000 - 500 = 500. 600 seconds (not enough time has passed)
        // if ((block.timestamp - s_lastTimeStamp) < i_interval) {
        //     revert();
        // }
        s_raffleState = RaffleState.CALCULATING;
        // Request for a random number:
        uint256 requestId = i_vrfCoordinator.requestRandomWords( // ChainlinkVRF Coordinator address; On every chain where ChainlinkVrRF exists there's and address that allows you to make a request to a Chainlink node
            i_gasLane, // gas lane, dependent on the chain
            i_subscriptionId,
            REQUEST_CONFIRMATIONS, // the number of block confirmations for your random number to be considered good; how many confirmations we want
            i_callBackGasLimit, // gas limit to make sure that we don't overspend on this call; the max gas that we want the callback function to do
            NUM_WORDS // number of random numbers
        );
        emit RequestedRaffleWinner(requestId); // this is the second event emitted in this transaction
        // the first one comes from "requestRandomWords" which is on VRFCoordinatorV2Mock.sol
        // and this is the first topic to refers to the entire event
    }

    function fulfillRandomWords(
        // we inherit it from VRFConsumerBaseV2
        uint256 /* requestId */,
        uint256[] memory randomWords
    ) internal override {
        // Checks: require (if -> errors)
        // Effects (Our own contract)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0); // resetting the array
        s_lastTimeStamp = block.timestamp; // start the clock over for the new lottery
        emit PickedWinner(winner); // we put this here because it's not an interaction with another contract
        // Interactions (Other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Function
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOrPlayers() external view returns (uint256) {
        return s_players.length;
    }
}
