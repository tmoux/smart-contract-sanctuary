pragma solidity ^0.4.24;

// File: contracts/library/SafeMath.sol

/**
 * @title SafeMath v0.1.9
 * @dev Math operations with safety checks that throw on error
 * change notes:  original SafeMath library from OpenZeppelin modified by Inventor
 * - added sqrt
 * - added sq
 * - added pwr 
 * - changed asserts to requires with error log outputs
 * - removed div, its useless
 */
library SafeMath {
    
    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) 
        internal 
        pure 
        returns (uint256 c) 
    {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        require(c / a == b, "SafeMath mul failed");
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn&#39;t hold
        return c;
    }
    
    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b)
        internal
        pure
        returns (uint256) 
    {
        require(b <= a, "SafeMath sub failed");
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b)
        internal
        pure
        returns (uint256 c) 
    {
        c = a + b;
        require(c >= a, "SafeMath add failed");
        return c;
    }
    
    /**
     * @dev gives square root of given x.
     */
    function sqrt(uint256 x)
        internal
        pure
        returns (uint256 y) 
    {
        uint256 z = ((add(x,1)) / 2);
        y = x;
        while (z < y) 
        {
            y = z;
            z = ((add((x / z),z)) / 2);
        }
    }
    
    /**
     * @dev gives square. multiplies x by x
     */
    function sq(uint256 x)
        internal
        pure
        returns (uint256)
    {
        return (mul(x,x));
    }
    
    /**
     * @dev x to the power of y 
     */
    function pwr(uint256 x, uint256 y)
        internal 
        pure 
        returns (uint256)
    {
        if (x==0)
            return (0);
        else if (y==0)
            return (1);
        else 
        {
            uint256 z = x;
            for (uint256 i=1; i < y; i++)
                z = mul(z,x);
            return (z);
        }
    }
}

// File: contracts/library/NameFilter.sol

library NameFilter {
    /**
     * @dev filters name strings
     * -converts uppercase to lower case.  
     * -makes sure it does not start/end with a space
     * -makes sure it does not contain multiple spaces in a row
     * -cannot be only numbers
     * -cannot start with 0x 
     * -restricts characters to A-Z, a-z, 0-9, and space.
     * @return reprocessed string in bytes32 format
     */
    function nameFilter(string _input)
        internal
        pure
        returns(bytes32)
    {
        bytes memory _temp = bytes(_input);
        uint256 _length = _temp.length;
        
        //sorry limited to 32 characters
        require (_length <= 32 && _length > 0, "string must be between 1 and 32 characters");
        // make sure it doesnt start with or end with space
        require(_temp[0] != 0x20 && _temp[_length-1] != 0x20, "string cannot start or end with space");
        // make sure first two characters are not 0x
        if (_temp[0] == 0x30)
        {
            require(_temp[1] != 0x78, "string cannot start with 0x");
            require(_temp[1] != 0x58, "string cannot start with 0X");
        }
        
        // create a bool to track if we have a non number character
        bool _hasNonNumber;
        
        // convert & check
        for (uint256 i = 0; i < _length; i++)
        {
            // if its uppercase A-Z
            if (_temp[i] > 0x40 && _temp[i] < 0x5b)
            {
                // convert to lower case a-z
                _temp[i] = byte(uint(_temp[i]) + 32);
                
                // we have a non number
                if (_hasNonNumber == false)
                    _hasNonNumber = true;
            } else {
                require
                (
                    // require character is a space
                    _temp[i] == 0x20 || 
                    // OR lowercase a-z
                    (_temp[i] > 0x60 && _temp[i] < 0x7b) ||
                    // or 0-9
                    (_temp[i] > 0x2f && _temp[i] < 0x3a),
                    "string contains invalid characters"
                );
                // make sure theres not 2x spaces in a row
                if (_temp[i] == 0x20)
                    require( _temp[i+1] != 0x20, "string cannot contain consecutive spaces");
                
                // see if we have a character other than a number
                if (_hasNonNumber == false && (_temp[i] < 0x30 || _temp[i] > 0x39))
                    _hasNonNumber = true;    
            }
        }
        
        require(_hasNonNumber == true, "string cannot be only numbers");
        
        bytes32 _ret;
        assembly {
            _ret := mload(add(_temp, 32))
        }
        return (_ret);
    }
}

// File: contracts/library/MSFun.sol

/** @title -MSFun- v0.2.4
 * ┌┬┐┌─┐┌─┐┌┬┐   ╦╦ ╦╔═╗╔╦╗  ┌─┐┬─┐┌─┐┌─┐┌─┐┌┐┌┌┬┐┌─┐
 *  │ ├┤ ├─┤│││   ║║ ║╚═╗ ║   ├─┘├┬┘├┤ └─┐├┤ │││ │ └─┐
 *  ┴ └─┘┴ ┴┴ ┴  ╚╝╚═╝╚═╝ ╩   ┴  ┴└─└─┘└─┘└─┘┘└┘ ┴ └─┘
 *                                  _____                      _____
 *                                 (, /     /)       /) /)    (, /      /)          /)
 *          ┌─┐                      /   _ (/_      // //       /  _   // _   __  _(/
 *          ├─┤                  ___/___(/_/(__(_/_(/_(/_   ___/__/_)_(/_(_(_/ (_(_(_
 *          ┴ ┴                /   /          .-/ _____   (__ /                               
 *                            (__ /          (_/ (, /                                      /)™ 
 *                                                 /  __  __ __ __  _   __ __  _  _/_ _  _(/
 * ┌─┐┬─┐┌─┐┌┬┐┬ ┬┌─┐┌┬┐                          /__/ (_(__(_)/ (_/_)_(_)/ (_(_(_(__(/_(_(_
 * ├─┘├┬┘│ │ │││ ││   │                      (__ /              .-/  &#169; Jekyll Island Inc. 2018
 * ┴  ┴└─└─┘─┴┘└─┘└─┘ ┴                                        (_/
 *  _           _             _  _  _  _             _  _  _  _  _                                      
 *=(_) _     _ (_)==========_(_)(_)(_)(_)_==========(_)(_)(_)(_)(_)================================*
 * (_)(_)   (_)(_)         (_)          (_)         (_)       _         _    _  _  _  _                 
 * (_) (_)_(_) (_)         (_)_  _  _  _            (_) _  _ (_)       (_)  (_)(_)(_)(_)_               
 * (_)   (_)   (_)           (_)(_)(_)(_)_          (_)(_)(_)(_)       (_)  (_)        (_)              
 * (_)         (_)  _  _    _           (_)  _  _   (_)      (_)       (_)  (_)        (_)  _  _        
 *=(_)=========(_)=(_)(_)==(_)_  _  _  _(_)=(_)(_)==(_)======(_)_  _  _(_)_ (_)========(_)=(_)(_)==*
 * (_)         (_) (_)(_)    (_)(_)(_)(_)   (_)(_)  (_)        (_)(_)(_) (_)(_)        (_) (_)(_)
 *
 * ╔═╗┌─┐┌┐┌┌┬┐┬─┐┌─┐┌─┐┌┬┐  ╔═╗┌─┐┌┬┐┌─┐ ┌──────────┐
 * ║  │ ││││ │ ├┬┘├─┤│   │   ║  │ │ ││├┤  │ Inventor │
 * ╚═╝└─┘┘└┘ ┴ ┴└─┴ ┴└─┘ ┴   ╚═╝└─┘─┴┘└─┘ └──────────┘
 *  
 *         ┌──────────────────────────────────────────────────────────────────────┐
 *         │ MSFun, is an importable library that gives your contract the ability │
 *         │ add multiSig requirement to functions.                               │
 *         └──────────────────────────────────────────────────────────────────────┘
 *                                ┌────────────────────┐
 *                                │ Setup Instructions │
 *                                └────────────────────┘
 * (Step 1) import the library into your contract
 * 
 *    import "./MSFun.sol";
 *
 * (Step 2) set up the signature data for msFun
 * 
 *     MSFun.Data private msData;
 *                                ┌────────────────────┐
 *                                │ Usage Instructions │
 *                                └────────────────────┘
 * at the beginning of a function
 * 
 *     function functionName() 
 *     {
 *         if (MSFun.multiSig(msData, required signatures, "functionName") == true)
 *         {
 *             MSFun.deleteProposal(msData, "functionName");
 * 
 *             // put function body here 
 *         }
 *     }
 *                           ┌────────────────────────────────┐
 *                           │ Optional Wrappers For TeamJust │
 *                           └────────────────────────────────┘
 * multiSig wrapper function (cuts down on inputs, improves readability)
 * this wrapper is HIGHLY recommended
 * 
 *     function multiSig(bytes32 _whatFunction) private returns (bool) {return(MSFun.multiSig(msData, TeamJust.requiredSignatures(), _whatFunction));}
 *     function multiSigDev(bytes32 _whatFunction) private returns (bool) {return(MSFun.multiSig(msData, TeamJust.requiredDevSignatures(), _whatFunction));}
 *
 * wrapper for delete proposal (makes code cleaner)
 *     
 *     function deleteProposal(bytes32 _whatFunction) private {MSFun.deleteProposal(msData, _whatFunction);}
 *                             ┌────────────────────────────┐
 *                             │ Utility & Vanity Functions │
 *                             └────────────────────────────┘
 * delete any proposal is highly recommended.  without it, if an admin calls a multiSig
 * function, with argument inputs that the other admins do not agree upon, the function
 * can never be executed until the undesirable arguments are approved.
 * 
 *     function deleteAnyProposal(bytes32 _whatFunction) onlyDevs() public {MSFun.deleteProposal(msData, _whatFunction);}
 * 
 * for viewing who has signed a proposal & proposal data
 *     
 *     function checkData(bytes32 _whatFunction) onlyAdmins() public view returns(bytes32, uint256) {return(MSFun.checkMsgData(msData, _whatFunction), MSFun.checkCount(msData, _whatFunction));}
 *
 * lets you check address of up to 3 signers (address)
 * 
 *     function checkSignersByAddress(bytes32 _whatFunction, uint256 _signerA, uint256 _signerB, uint256 _signerC) onlyAdmins() public view returns(address, address, address) {return(MSFun.checkSigner(msData, _whatFunction, _signerA), MSFun.checkSigner(msData, _whatFunction, _signerB), MSFun.checkSigner(msData, _whatFunction, _signerC));}
 *
 * same as above but will return names in string format.
 *
 *     function checkSignersByName(bytes32 _whatFunction, uint256 _signerA, uint256 _signerB, uint256 _signerC) onlyAdmins() public view returns(bytes32, bytes32, bytes32) {return(TeamJust.adminName(MSFun.checkSigner(msData, _whatFunction, _signerA)), TeamJust.adminName(MSFun.checkSigner(msData, _whatFunction, _signerB)), TeamJust.adminName(MSFun.checkSigner(msData, _whatFunction, _signerC)));}
 *                             ┌──────────────────────────┐
 *                             │ Functions In Depth Guide │
 *                             └──────────────────────────┘
 * In the following examples, the Data is the proposal set for this library.  And
 * the bytes32 is the name of the function.
 *
 * MSFun.multiSig(Data, uint256, bytes32) - Manages creating/updating multiSig 
 *      proposal for the function being called.  The uint256 is the required 
 *      number of signatures needed before the multiSig will return true.  
 *      Upon first call, multiSig will create a proposal and store the arguments 
 *      passed with the function call as msgData.  Any admins trying to sign the 
 *      function call will need to send the same argument values. Once required
 *      number of signatures is reached this will return a bool of true.
 * 
 * MSFun.deleteProposal(Data, bytes32) - once multiSig unlocks the function body,
 *      you will want to delete the proposal data.  This does that.
 *
 * MSFun.checkMsgData(Data, bytes32) - checks the message data for any given proposal 
 * 
 * MSFun.checkCount(Data, bytes32) - checks the number of admins that have signed
 *      the proposal 
 * 
 * MSFun.checkSigners(data, bytes32, uint256) - checks the address of a given signer.
 *      the uint256, is the log number of the signer (ie 1st signer, 2nd signer)
 */

library MSFun {
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // DATA SETS
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // contact data setup
    struct Data 
    {
        mapping (bytes32 => ProposalData) proposal_;
    }
    struct ProposalData 
    {
        // a hash of msg.data 
        bytes32 msgData;
        // number of signers
        uint256 count;
        // tracking of wither admins have signed
        mapping (address => bool) admin;
        // list of admins who have signed
        mapping (uint256 => address) log;
    }
    
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // MULTI SIG FUNCTIONS
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    function multiSig(Data storage self, uint256 _requiredSignatures, bytes32 _whatFunction)
        internal
        returns(bool) 
    {
        // our proposal key will be a hash of our function name + our contracts address 
        // by adding our contracts address to this, we prevent anyone trying to circumvent
        // the proposal&#39;s security via external calls.
        bytes32 _whatProposal = whatProposal(_whatFunction);
        
        // this is just done to make the code more readable.  grabs the signature count
        uint256 _currentCount = self.proposal_[_whatProposal].count;
        
        // store the address of the person sending the function call.  we use msg.sender 
        // here as a layer of security.  in case someone imports our contract and tries to 
        // circumvent function arguments.  still though, our contract that imports this
        // library and calls multisig, needs to use onlyAdmin modifiers or anyone who
        // calls the function will be a signer. 
        address _whichAdmin = msg.sender;
        
        // prepare our msg data.  by storing this we are able to verify that all admins
        // are approving the same argument input to be executed for the function.  we hash 
        // it and store in bytes32 so its size is known and comparable
        bytes32 _msgData = keccak256(msg.data);
        
        // check to see if this is a new execution of this proposal or not
        if (_currentCount == 0)
        {
            // if it is, lets record the original signers data
            self.proposal_[_whatProposal].msgData = _msgData;
            
            // record original senders signature
            self.proposal_[_whatProposal].admin[_whichAdmin] = true;        
            
            // update log (used to delete records later, and easy way to view signers)
            // also useful if the calling function wants to give something to a 
            // specific signer.  
            self.proposal_[_whatProposal].log[_currentCount] = _whichAdmin;  
            
            // track number of signatures
            self.proposal_[_whatProposal].count += 1;  
            
            // if we now have enough signatures to execute the function, lets
            // return a bool of true.  we put this here in case the required signatures
            // is set to 1.
            if (self.proposal_[_whatProposal].count == _requiredSignatures) {
                return(true);
            }            
        // if its not the first execution, lets make sure the msgData matches
        } else if (self.proposal_[_whatProposal].msgData == _msgData) {
            // msgData is a match
            // make sure admin hasnt already signed
            if (self.proposal_[_whatProposal].admin[_whichAdmin] == false) 
            {
                // record their signature
                self.proposal_[_whatProposal].admin[_whichAdmin] = true;        
                
                // update log (used to delete records later, and easy way to view signers)
                self.proposal_[_whatProposal].log[_currentCount] = _whichAdmin;  
                
                // track number of signatures
                self.proposal_[_whatProposal].count += 1;  
            }
            
            // if we now have enough signatures to execute the function, lets
            // return a bool of true.
            // we put this here for a few reasons.  (1) in normal operation, if 
            // that last recorded signature got us to our required signatures.  we 
            // need to return bool of true.  (2) if we have a situation where the 
            // required number of signatures was adjusted to at or lower than our current 
            // signature count, by putting this here, an admin who has already signed,
            // can call the function again to make it return a true bool.  but only if
            // they submit the correct msg data
            if (self.proposal_[_whatProposal].count == _requiredSignatures) {
                return(true);
            }
        }
    }
    
    
    // deletes proposal signature data after successfully executing a multiSig function
    function deleteProposal(Data storage self, bytes32 _whatFunction)
        internal
    {
        //done for readability sake
        bytes32 _whatProposal = whatProposal(_whatFunction);
        address _whichAdmin;
        
        //delete the admins votes & log.   i know for loops are terrible.  but we have to do this 
        //for our data stored in mappings.  simply deleting the proposal itself wouldn&#39;t accomplish this.
        for (uint256 i=0; i < self.proposal_[_whatProposal].count; i++) {
            _whichAdmin = self.proposal_[_whatProposal].log[i];
            delete self.proposal_[_whatProposal].admin[_whichAdmin];
            delete self.proposal_[_whatProposal].log[i];
        }
        //delete the rest of the data in the record
        delete self.proposal_[_whatProposal];
    }
    
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // HELPER FUNCTIONS
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

    function whatProposal(bytes32 _whatFunction)
        private
        view
        returns(bytes32)
    {
        return(keccak256(abi.encodePacked(_whatFunction,this)));
    }
    
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // VANITY FUNCTIONS
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // returns a hashed version of msg.data sent by original signer for any given function
    function checkMsgData (Data storage self, bytes32 _whatFunction)
        internal
        view
        returns (bytes32 msg_data)
    {
        bytes32 _whatProposal = whatProposal(_whatFunction);
        return (self.proposal_[_whatProposal].msgData);
    }
    
    // returns number of signers for any given function
    function checkCount (Data storage self, bytes32 _whatFunction)
        internal
        view
        returns (uint256 signature_count)
    {
        bytes32 _whatProposal = whatProposal(_whatFunction);
        return (self.proposal_[_whatProposal].count);
    }
    
    // returns address of an admin who signed for any given function
    function checkSigner (Data storage self, bytes32 _whatFunction, uint256 _signer)
        internal
        view
        returns (address signer)
    {
        require(_signer > 0, "MSFun checkSigner failed - 0 not allowed");
        bytes32 _whatProposal = whatProposal(_whatFunction);
        return (self.proposal_[_whatProposal].log[_signer - 1]);
    }
}

// File: contracts/interface/PlayerBookReceiverInterface.sol

interface PlayerBookReceiverInterface {
    function receivePlayerInfo(uint256 _pID, address _addr, bytes32 _name, uint256 _laff, uint8 _level) external;
    function receivePlayerNameList(uint256 _pID, bytes32 _name) external;
}

// File: contracts/PlayerBook.sol

/*
 * -PlayerBook - v-x
 *     ______   _                                 ______                 _          
 *====(_____ \=| |===============================(____  \===============| |=============*
 *     _____) )| |  _____  _   _  _____   ____    ____)  )  ___    ___  | |  _
 *    |  ____/ | | (____ || | | || ___ | / ___)  |  __  (  / _ \  / _ \ | |_/ )
 *    | |      | | / ___ || |_| || ____|| |      | |__)  )| |_| || |_| ||  _ (
 *====|_|=======\_)\_____|=\__  ||_____)|_|======|______/==\___/==\___/=|_|=\_)=========*
 *                        (____/
 * ╔═╗┌─┐┌┐┌┌┬┐┬─┐┌─┐┌─┐┌┬┐  ╔═╗┌─┐┌┬┐┌─┐ ┌──────────┐                       
 * ║  │ ││││ │ ├┬┘├─┤│   │   ║  │ │ ││├┤  │          │
 * ╚═╝└─┘┘└┘ ┴ ┴└─┴ ┴└─┘ ┴   ╚═╝└─┘─┴┘└─┘ └──────────┘    
 */






contract PlayerBook {
    using NameFilter for string;
    using SafeMath for uint256;

    address private Community_Wallet1 = 0x00839c9d56F48E17d410E94309C91B9639D48242;
    address private Community_Wallet2 = 0x53bB6E7654155b8bdb5C4c6e41C9f47Cd8Ed1814;
    
    MSFun.Data private msData;
    function deleteProposal(bytes32 _whatFunction) private {MSFun.deleteProposal(msData, _whatFunction);}
    function deleteAnyProposal(bytes32 _whatFunction) onlyDevs() public {MSFun.deleteProposal(msData, _whatFunction);}
    function checkData(bytes32 _whatFunction) onlyDevs() public view returns(bytes32, uint256) {return(MSFun.checkMsgData(msData, _whatFunction), MSFun.checkCount(msData, _whatFunction));}
    function checkSignersByAddress(bytes32 _whatFunction, uint256 _signerA, uint256 _signerB, uint256 _signerC) onlyDevs() public view returns(address, address, address) {return(MSFun.checkSigner(msData, _whatFunction, _signerA), MSFun.checkSigner(msData, _whatFunction, _signerB), MSFun.checkSigner(msData, _whatFunction, _signerC));}
//==============================================================================
//     _| _ _|_ _    _ _ _|_    _   .
//    (_|(_| | (_|  _\(/_ | |_||_)  .
//=============================|================================================    
    uint256 public registrationFee_ = 10 finney;            // price to register a name
    mapping(uint256 => PlayerBookReceiverInterface) public games_;  // mapping of our game interfaces for sending your account info to games
    mapping(address => bytes32) public gameNames_;          // lookup a games name
    mapping(address => uint256) public gameIDs_;            // lokup a games ID
    uint256 public gID_;        // total number of games
    uint256 public pID_;        // total number of players
    mapping (address => uint256) public pIDxAddr_;          // (addr => pID) returns player id by address
    mapping (bytes32 => uint256) public pIDxName_;          // (name => pID) returns player id by name
    mapping (uint256 => Player) public plyr_;               // (pID => data) player data
    mapping (uint256 => mapping (bytes32 => bool)) public plyrNames_; // (pID => name => bool) list of names a player owns.  (used so you can change your display name amoungst any name you own)
    mapping (uint256 => mapping (uint256 => bytes32)) public plyrNameList_; // (pID => nameNum => name) list of names a player owns
    struct Player {
        address addr;
        bytes32 name;
        uint256 laff;
        uint256 names;
        uint256 rreward;
        //for rank board
        uint256 cost; //everyone charges per round
        uint32 round; //rank round number for players
        uint8 level;
    }

    event eveSuperPlayer(bytes32 _name, uint256 _pid, address _addr, uint8 _level);
    event eveResolve(uint256 _startBlockNumber, uint32 _roundNumber);
    event eveUpdate(uint256 _pID, uint32 _roundNumber, uint256 _roundCost, uint256 _cost);
    event eveDeposit(address _from, uint256 _value, uint256 _balance );
    event eveReward(uint256 _pID, uint256 _have, uint256 _reward, uint256 _vault, uint256 _allcost, uint256 _lastRefrralsVault );
    event eveWithdraw(uint256 _pID, address _addr, uint256 _reward, uint256 _balance );
    event eveSetAffID(uint256 _pID, address _addr, uint256 _laff, address _affAddr );


    mapping (uint8 => uint256) public levelValue_;

    //for super player
    uint256[] public superPlayers_;

    //rank board data
    uint256[] public rankPlayers_;
    uint256[] public rankCost_;    

    //the eth of refrerrals
    uint256 public referralsVault_;
    //the last rank round refrefrrals
    uint256 public lastRefrralsVault_;

    //time per round, the ethernum generate one block per 15 seconds, it will generate 24*60*60/15 blocks  per 24h
    uint256 constant public roundBlockCount_ = 5760;
    //the start block numnber when the rank board had been activted for first time
    uint256 public startBlockNumber_;

    //rank top 10
    uint8 constant public rankNumbers_ = 10;
    //current round number
    uint32 public roundNumber_;

    


//==============================================================================
//     _ _  _  __|_ _    __|_ _  _  .
//    (_(_)| |_\ | | |_|(_ | (_)|   .  (initial data setup upon contract deploy)
//==============================================================================

    constructor()
        public
    {
        levelValue_[3] = 0.003 ether;
        levelValue_[2] = 0.3 ether;
        levelValue_[1] = 1.5 ether;

        // premine the dev names (sorry not sorry)
        // No keys are purchased with this method, it&#39;s simply locking our addresses,
        // PID&#39;s and names for referral codes.

        pID_ = 0;
        rankPlayers_.length = rankNumbers_;
        rankCost_.length = rankNumbers_;
        roundNumber_ = 0;
        startBlockNumber_ = block.number;
        referralsVault_ = 0;
        lastRefrralsVault_ =0;

        
        addSuperPlayer(0x008d20ea31021bb4C93F3051aD7763523BBb0481,"main",1);
        addSuperPlayer(0x00De30E1A0E82750ea1f96f6D27e112f5c8A352D,"go",1);

        //
        addSuperPlayer(0x26042eb2f06D419093313ae2486fb40167Ba349C,"jack",1);
        addSuperPlayer(0x8d60d529c435e2A4c67FD233c49C3F174AfC72A8,"leon",1);
        addSuperPlayer(0xF9f24b9a5FcFf3542Ae3361c394AD951a8C0B3e1,"zuopiezi",1);
        addSuperPlayer(0x9ca974f2c49d68bd5958978e81151e6831290f57,"cowkeys",1);
        addSuperPlayer(0xf22978ed49631b68409a16afa8e123674115011e,"vulcan",1);
        addSuperPlayer(0x00b22a1D6CFF93831Cf2842993eFBB2181ad78de,"neo",1);
        //
        addSuperPlayer(0x10a04F6b13E95Bf8cC82187536b87A8646f1Bd9d,"mydream",1);

        //
        addSuperPlayer(0xce7aed496f69e2afdb99979952d9be8a38ad941d,"uking",1);
        addSuperPlayer(0x43fbedf2b2620ccfbd33d5c735b12066ff2fcdc1,"agg",1);

    }
//==============================================================================
//     _ _  _  _|. |`. _  _ _  .
//    | | |(_)(_||~|~|(/_| _\  .  (these are safety checks)
//==============================================================================    
    /**
     * @dev prevents contracts from interacting with fomo3d 
     */
    modifier isHuman() {
        address _addr = msg.sender;
        uint256 _codeLength;
        
        assembly {_codeLength := extcodesize(_addr)}
        require(_codeLength == 0, "sorry humans only");
        _;
    }

    // only player with reward
    modifier onlyHaveReward() {
        require(myReward() > 0);
        _;
    }

    // check address
    modifier validAddress( address addr ) {
        require(addr != address(0x0));
        _;
    }

    //devs check    
    modifier onlyDevs(){
        require(
            //msg.sender == 0x00D8E8CCb4A29625D299798036825f3fa349f2b4 ||//for test
            msg.sender == 0x00A32C09c8962AEc444ABde1991469eD0a9ccAf7 ||
            msg.sender == 0x00aBBff93b10Ece374B14abb70c4e588BA1F799F,
            "only dev"
        );
        _;
    }

    //level check
    modifier isLevel(uint8 _level) {
        require(_level >= 0 && _level <= 3, "invalid level");
        require(msg.value >= levelValue_[_level], "sorry request price less than affiliate level");
        _;
    }
    
    modifier isRegisteredGame()
    {
        require(gameIDs_[msg.sender] != 0);
        _;
    }
//==============================================================================
//     _    _  _ _|_ _  .
//    (/_\/(/_| | | _\  .
//==============================================================================    
    // fired whenever a player registers a name
    event onNewName
    (
        uint256 indexed playerID,
        address indexed playerAddress,
        bytes32 indexed playerName,
        bool isNewPlayer,
        uint256 affiliateID,
        address affiliateAddress,
        bytes32 affiliateName,
        uint256 amountPaid,
        uint256 timeStamp
    );


//==============================================================================
//   _ _ _|_    _   .
//  _\(/_ | |_||_)  .
//=============|================================================================
    function addSuperPlayer(address _addr, bytes32 _name, uint8 _level)
        private
    {        
        pID_++;

        plyr_[pID_].addr = _addr;
        plyr_[pID_].name = _name;
        plyr_[pID_].names = 1;
        plyr_[pID_].level = _level;
        pIDxAddr_[_addr] = pID_;
        pIDxName_[_name] = pID_;
        plyrNames_[pID_][_name] = true;
        plyrNameList_[pID_][1] = _name;

        superPlayers_.push(pID_);

        //fire event
        emit eveSuperPlayer(_name,pID_,_addr,_level);        
    }
    
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // BALANCE
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    function balances()
        public
        view
        returns(uint256)
    {
        return (address(this).balance);
    }
    
    
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    // DEPOSIT
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    function deposit()
        validAddress(msg.sender)
        external
        payable
        returns (bool)
    {
        if(msg.value>0){
            referralsVault_ += msg.value;

            emit eveDeposit(msg.sender, msg.value, address(this).balance);

            return true;
        }
        return false;
    }

    function updateRankBoard(uint256 _pID,uint256 _cost)
        isRegisteredGame()
        validAddress(msg.sender)    
        external
    {
        uint256 _affID = plyr_[_pID].laff;
        if(_affID<=0){
            return ;
        }

        if(_cost<=0){
            return ;
        }
        //just for level 3 player
        if(plyr_[_affID].level != 3){
            return ;
        }

        uint256 _affReward = _cost.mul(5)/100;

        //calc round charge
        if(  plyr_[_affID].round == roundNumber_ ){
            //same round
            plyr_[_affID].cost += _affReward;
        }
        else{
            //diffrent round
            plyr_[_affID].cost = _affReward;
            plyr_[_affID].round = roundNumber_;
        }
        //check board players
        bool inBoard = false;
        for( uint8 i=0; i<rankNumbers_; i++ ){
            if(  _affID == rankPlayers_[i] ){
                //update
                inBoard = true;
                rankCost_[i] = plyr_[_affID].cost;
                break;
            }
        }
        if( inBoard == false ){
            //find the min charge  player
            uint256 minCost = plyr_[_affID].cost;
            uint8 minIndex = rankNumbers_;
            for( uint8  k=0; k<rankNumbers_; k++){
                if( rankCost_[k] < minCost){
                    minIndex = k;
                    minCost = rankCost_[k];
                }            
            }
            if( minIndex != rankNumbers_ ){
                //replace
                rankPlayers_[minIndex] =  _affID;
                rankCost_[minIndex] = plyr_[_affID].cost;
            }
        }

        emit eveUpdate( _affID,roundNumber_,plyr_[_affID].cost,_cost);

    }

    //
    function resolveRankBoard() 
        //isRegisteredGame()
        validAddress(msg.sender) 
        external
    {
        uint256 deltaBlockCount = block.number - startBlockNumber_;
        if( deltaBlockCount < roundBlockCount_ ){
            return;
        }
        //update start block number
        startBlockNumber_ = block.number;
        //
        emit eveResolve(startBlockNumber_,roundNumber_);
	   
        roundNumber_++;
        //reward
        uint256 allCost = 0;
        for( uint8 k=0; k<rankNumbers_; k++){
            allCost += rankCost_[k];
        }

        if( allCost > 0 ){
            uint256 reward = 0;
            uint256 roundVault = referralsVault_.sub(lastRefrralsVault_);
            for( uint8 m=0; m<rankNumbers_; m++){                
                uint256 pid = rankPlayers_[m];
                if( pid>0 ){
                    reward = (roundVault.mul(8)/10).mul(rankCost_[m])/allCost;
                    lastRefrralsVault_ += reward;
                    plyr_[pid].rreward += reward;
                    emit eveReward(rankPlayers_[m],plyr_[pid].rreward, reward,referralsVault_,allCost, lastRefrralsVault_);
                }    
            }
        }
        
        //reset rank data
        rankPlayers_.length=0;
        rankCost_.length=0;

        rankPlayers_.length=10;
        rankCost_.length=10;
    }
    
    /**
     * Withdraws all of the callers earnings.
     */
    function myReward()
        public
        view
        returns(uint256)
    {
        uint256 pid = pIDxAddr_[msg.sender];
        return plyr_[pid].rreward;
    }

    function withdraw()
        onlyHaveReward()
        isHuman()
        public
    {
        address addr = msg.sender;
        uint256 pid = pIDxAddr_[addr];
        uint256 reward = plyr_[pid].rreward;
        
        //reset
        plyr_[pid].rreward = 0;

        //get reward
        addr.transfer(reward);
        
        // fire event
        emit eveWithdraw(pIDxAddr_[addr], addr, reward, balances());
    }
//==============================================================================
//     _  _ _|__|_ _  _ _  .
//    (_|(/_ |  | (/_| _\  . (for UI & viewing things on etherscan)
//=====_|=======================================================================
    function checkIfNameValid(string _nameStr)
        public
        view
        returns(bool)
    {
        bytes32 _name = _nameStr.nameFilter();
        if (pIDxName_[_name] == 0)
            return (true);
        else 
            return (false);
    }
//==============================================================================
//     _    |_ |. _   |`    _  __|_. _  _  _  .
//    |_)|_||_)||(_  ~|~|_|| |(_ | |(_)| |_\  .  (use these to interact with contract)
//====|=========================================================================    
    /**
     * @dev registers a name.  UI will always display the last name you registered.
     * but you will still own all previously registered names to use as affiliate 
     * links.
     * - must pay a registration fee.
     * - name must be unique
     * - names will be converted to lowercase
     * - name cannot start or end with a space 
     * - cannot have more than 1 space in a row
     * - cannot be only numbers
     * - cannot start with 0x 
     * - name must be at least 1 char
     * - max length of 32 characters long
     * - allowed characters: a-z, 0-9, and space
     * -functionhash- 0x921dec21 (using ID for affiliate)
     * -functionhash- 0x3ddd4698 (using address for affiliate)
     * -functionhash- 0x685ffd83 (using name for affiliate)
     * @param _nameString players desired name
     * @param _affCode affiliate ID, address, or name of who refered you
     * @param _all set to true if you want this to push your info to all games 
     * (this might cost a lot of gas)
     */
    function registerNameXID(string _nameString, uint256 _affCode, bool _all, uint8 _level)
        isHuman()
        isLevel(_level)
        public
        payable 
    {
        // make sure name fees paid
        require (msg.value >= registrationFee_, "umm.....  you have to pay the name fee");
        
        // filter name + condition checks
        bytes32 _name = NameFilter.nameFilter(_nameString);
        
        // set up address 
        address _addr = msg.sender;
        
        // set up our tx event data and determine if player is new or not
        bool _isNewPlayer = determinePID(_addr);
        
        // fetch player id
        uint256 _pID = pIDxAddr_[_addr];
        
        // manage affiliate residuals
        // if no affiliate code was given, no new affiliate code was given, or the 
        // player tried to use their own pID as an affiliate code, lolz
        if (_affCode != 0 && _affCode != plyr_[_pID].laff && _affCode != _pID) 
        {
            // update last affiliate 
            plyr_[_pID].laff = _affCode;
        } else if (_affCode == _pID) {
            _affCode = 0;
        }
        
        // register name 

        registerNameCore(_pID, _addr, _affCode, _name, _isNewPlayer, _all, _level);
    }
    
    function registerNameXaddr(string _nameString, address _affCode, bool _all, uint8 _level)
        isHuman()
        isLevel(_level)
        public
        payable 
    {
        // make sure name fees paid
        require (msg.value >= registrationFee_, "umm.....  you have to pay the name fee");
        
        // filter name + condition checks
        bytes32 _name = NameFilter.nameFilter(_nameString);
        
        // set up address 
        address _addr = msg.sender;
        
        // set up our tx event data and determine if player is new or not
        bool _isNewPlayer = determinePID(_addr);
        
        // fetch player id
        uint256 _pID = pIDxAddr_[_addr];
        
        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if (_affCode != address(0) && _affCode != _addr)
        {
            // get affiliate ID from aff Code 
            _affID = pIDxAddr_[_affCode];
            
            // if affID is not the same as previously stored 
            if (_affID != plyr_[_pID].laff)
            {
                // update last affiliate
                plyr_[_pID].laff = _affID;
            }
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all, _level);
    }
    
    function registerNameXname(string _nameString, bytes32 _affCode, bool _all, uint8 _level)
        isHuman()
        isLevel(_level)
        public
        payable 
    {
        // make sure name fees paid
        require (msg.value >= registrationFee_, "umm.....  you have to pay the name fee");
        
        // filter name + condition checks
        bytes32 _name = NameFilter.nameFilter(_nameString);
        
        // set up address 
        address _addr = msg.sender;
        
        // set up our tx event data and determine if player is new or not
        bool _isNewPlayer = determinePID(_addr);
        
        // fetch player id
        uint256 _pID = pIDxAddr_[_addr];
        
        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if (_affCode != "" && _affCode != _name)
        {
            // get affiliate ID from aff Code 
            _affID = pIDxName_[_affCode];
            
            // if affID is not the same as previously stored 
            if (_affID != plyr_[_pID].laff)
            {
                // update last affiliate
                plyr_[_pID].laff = _affID;
            }
        }
        
        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all, _level);
    }
    
    /**
     * @dev players, if you registered a profile, before a game was released, or
     * set the all bool to false when you registered, use this function to push
     * your profile to a single game.  also, if you&#39;ve  updated your name, you
     * can use this to push your name to games of your choosing.
     * -functionhash- 0x81c5b206
     * @param _gameID game id 
     */
    function addMeToGame(uint256 _gameID)
        isHuman()
        public
    {
        require(_gameID <= gID_, "silly player, that game doesn&#39;t exist yet");
        address _addr = msg.sender;
        uint256 _pID = pIDxAddr_[_addr];
        require(_pID != 0, "hey there buddy, you dont even have an account");
        uint256 _totalNames = plyr_[_pID].names;
        
        // add players profile and most recent name
        games_[_gameID].receivePlayerInfo(_pID, _addr, plyr_[_pID].name, plyr_[_pID].laff, 0);
        
        // add list of all names
        if (_totalNames > 1)
            for (uint256 ii = 1; ii <= _totalNames; ii++)
                games_[_gameID].receivePlayerNameList(_pID, plyrNameList_[_pID][ii]);
    }
    
    /**
     * @dev players, use this to push your player profile to all registered games.
     * -functionhash- 0x0c6940ea
     */
    function addMeToAllGames()
        isHuman()
        public
    {
        address _addr = msg.sender;
        uint256 _pID = pIDxAddr_[_addr];
        require(_pID != 0, "hey there buddy, you dont even have an account");
        uint256 _laff = plyr_[_pID].laff;
        uint256 _totalNames = plyr_[_pID].names;
        bytes32 _name = plyr_[_pID].name;
        
        for (uint256 i = 1; i <= gID_; i++)
        {
            games_[i].receivePlayerInfo(_pID, _addr, _name, _laff, 0);
            if (_totalNames > 1)
                for (uint256 ii = 1; ii <= _totalNames; ii++)
                    games_[i].receivePlayerNameList(_pID, plyrNameList_[_pID][ii]);
        }
                
    }
    
    /**
     * @dev players use this to change back to one of your old names.  tip, you&#39;ll
     * still need to push that info to existing games.
     * -functionhash- 0xb9291296
     * @param _nameString the name you want to use 
     */
    function useMyOldName(string _nameString)
        isHuman()
        public 
    {
        // filter name, and get pID
        bytes32 _name = _nameString.nameFilter();
        uint256 _pID = pIDxAddr_[msg.sender];
        
        // make sure they own the name 
        require(plyrNames_[_pID][_name] == true, "umm... thats not a name you own");
        
        // update their current name 
        plyr_[_pID].name = _name;
    }
    
//==============================================================================
//     _ _  _ _   | _  _ . _  .
//    (_(_)| (/_  |(_)(_||(_  . 
//=====================_|=======================================================    
    function registerNameCore(uint256 _pID, address _addr, uint256 _affID, bytes32 _name, bool _isNewPlayer, bool _all, uint8 _level)
        private
    {
        // if names already has been used, require that current msg sender owns the name
        if( pIDxName_[_name] == _pID && _pID !=0 ){
            //level up must keep old name!
            if (_level >= plyr_[_pID].level ) {
                require(plyrNames_[_pID][_name] == true, "sorry that names already taken");
            }
        }
        else if (pIDxName_[_name] != 0){
            require(plyrNames_[_pID][_name] == true, "sorry that names already taken");
        }
        // add name to player profile, registry, and name book
        plyr_[_pID].name = _name;
        plyr_[_pID].level = _level;

        pIDxName_[_name] = _pID;
        if (plyrNames_[_pID][_name] == false)
        {
            plyrNames_[_pID][_name] = true;
            plyr_[_pID].names++;
            plyrNameList_[_pID][plyr_[_pID].names] = _name;
        }

        // registration fee goes directly to community rewards
        Community_Wallet1.transfer(msg.value / 2);
        Community_Wallet2.transfer(msg.value / 2);
        
        // push player info to games
        if (_all == true)
            for (uint256 i = 1; i <= gID_; i++)
                games_[i].receivePlayerInfo(_pID, _addr, _name, _affID, _level);
        
        // fire event
        emit onNewName(_pID, _addr, _name, _isNewPlayer, _affID, plyr_[_affID].addr, plyr_[_affID].name, msg.value, now);
    }
//==============================================================================
//    _|_ _  _ | _  .
//     | (_)(_)|_\  .
//==============================================================================    
    function determinePID(address _addr)
        private
        returns (bool)
    {
        if (pIDxAddr_[_addr] == 0)
        {
            pID_++;
            pIDxAddr_[_addr] = pID_;
            plyr_[pID_].addr = _addr;
            
            // set the new player bool to true
            return (true);
        } else {
            return (false);
        }
    }
//==============================================================================
//   _   _|_ _  _ _  _ |   _ _ || _  .
//  (/_>< | (/_| | |(_||  (_(_|||_\  .
//==============================================================================
    function getPlayerID(address _addr)
        isRegisteredGame()
        external
        returns (uint256)
    {
        determinePID(_addr);
        return (pIDxAddr_[_addr]);
    }
    function getPlayerName(uint256 _pID)
        external
        view
        returns (bytes32)
    {
        return (plyr_[_pID].name);
    }
    function getPlayerLAff(uint256 _pID)
        external
        view
        returns (uint256)
    {
        return (plyr_[_pID].laff);
    }
    function getPlayerAddr(uint256 _pID)
        external
        view
        returns (address)
    {
        return (plyr_[_pID].addr);
    }
    function getPlayerLevel(uint256 _pID)
        external
        view
        returns (uint8)
    {
        return (plyr_[_pID].level);
    }
    function getNameFee()
        external
        view
        returns (uint256)
    {
        return(registrationFee_);
    }

    function setPlayerAffID(uint256 _pID,uint256 _laff)
        isRegisteredGame()
        external
    {
        plyr_[_pID].laff = _laff;

        emit eveSetAffID(_pID, plyr_[_pID].addr, _laff, plyr_[_laff].addr);
    }

    function registerNameXIDFromDapp(address _addr, bytes32 _name, uint256 _affCode, bool _all, uint8 _level)
        isRegisteredGame()
        isLevel(_level)
        external
        payable
        returns(bool, uint256)
    {
        // make sure name fees paid //TODO 已经通过 islevel
        //require (msg.value >= registrationFee_, "umm.....  you have to pay the name fee");
        
        // set up our tx event data and determine if player is new or not
        bool _isNewPlayer = determinePID(_addr);
        
        // fetch player id
        uint256 _pID = pIDxAddr_[_addr];
        
        // manage affiliate residuals
        // if no affiliate code was given, no new affiliate code was given, or the 
        // player tried to use their own pID as an affiliate code, lolz
        uint256 _affID = _affCode;
        if (_affID != 0 && _affID != plyr_[_pID].laff && _affID != _pID) 
        {
            // update last affiliate
            if (plyr_[_pID].laff == 0)
                plyr_[_pID].laff = _affID;
        } else if (_affID == _pID) {
            _affID = 0;
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all, _level);
        
        return(_isNewPlayer, _affID);
    }
    function registerNameXaddrFromDapp(address _addr, bytes32 _name, address _affCode, bool _all, uint8 _level)
        isRegisteredGame()
        isLevel(_level)
        external
        payable
        returns(bool, uint256)
    {
        // make sure name fees paid //TODO 已经通过 islevel
        //require (msg.value >= registrationFee_, "umm.....  you have to pay the name fee");
        
        // set up our tx event data and determine if player is new or not
        bool _isNewPlayer = determinePID(_addr);
        
        // fetch player id
        uint256 _pID = pIDxAddr_[_addr];
        
        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if (_affCode != address(0) && _affCode != _addr)
        {
            // get affiliate ID from aff Code 
            _affID = pIDxAddr_[_affCode];
            
            // if affID is not the same as previously stored 
            if (_affID != plyr_[_pID].laff)
            {
                // update last affiliate
                if (plyr_[_pID].laff == 0)
                    plyr_[_pID].laff = _affID;
            }
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all, _level);
        
        return(_isNewPlayer, _affID);
    }
    function registerNameXnameFromDapp(address _addr, bytes32 _name, bytes32 _affCode, bool _all, uint8 _level)
        isRegisteredGame()
        isLevel(_level)
        external
        payable
        returns(bool, uint256)
    {
        // make sure name fees paid //TODO 已经通过 islevel
        //require (msg.value >= registrationFee_, "umm.....  you have to pay the name fee");
        
        // set up our tx event data and determine if player is new or not
        bool _isNewPlayer = determinePID(_addr);
        
        // fetch player id
        uint256 _pID = pIDxAddr_[_addr];
        
        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if (_affCode != "" && _affCode != _name)
        {
            // get affiliate ID from aff Code 
            _affID = pIDxName_[_affCode];
            
            // if affID is not the same as previously stored 
            if (_affID != plyr_[_pID].laff)
            {
                // update last affiliate
                if (plyr_[_pID].laff == 0)
                    plyr_[_pID].laff = _affID;
            }
        }
       
        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all, _level);
        
        return(_isNewPlayer, _affID);
    }
    
//==============================================================================
//   _ _ _|_    _   .
//  _\(/_ | |_||_)  .
//=============|================================================================
    function addGame(address _gameAddress, string _gameNameStr)
        onlyDevs()
        public
    {
        require(gameIDs_[_gameAddress] == 0, "derp, that games already been registered");


        deleteProposal("addGame");
        gID_++;
        bytes32 _name = _gameNameStr.nameFilter();
        gameIDs_[_gameAddress] = gID_;
        gameNames_[_gameAddress] = _name;
        games_[gID_] = PlayerBookReceiverInterface(_gameAddress);

        for(uint8 i=0; i<superPlayers_.length; i++){
            uint256 pid =superPlayers_[i];
            if( pid > 0 ){
                games_[gID_].receivePlayerInfo(pid, plyr_[pid].addr, plyr_[pid].name, 0, plyr_[pid].level);
            }
        }

    }
    
    function setRegistrationFee(uint256 _fee)
        onlyDevs()
        public
    {
        deleteProposal("setRegistrationFee");
        registrationFee_ = _fee;
    }
}