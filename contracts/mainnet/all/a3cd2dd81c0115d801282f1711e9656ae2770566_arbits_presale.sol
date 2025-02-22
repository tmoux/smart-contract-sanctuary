pragma solidity 0.4.24;

// File: contracts\safe_math_lib.sol

/**
 * @title SafeMath
 * @dev Math operations with safety checks that revert on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, reverts on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring &#39;a&#39; not being zero, but the
        // benefit is lost if &#39;b&#39; is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
    * @dev Integer division of two numbers truncating the quotient, reverts on division by zero.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0); // Solidity only automatically asserts when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn&#39;t hold

        return c;
    }

    /**
    * @dev Subtracts two numbers, reverts on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
    * @dev Adds two numbers, reverts on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
    * @dev Divides two numbers and returns the remainder (unsigned integer modulo),
    * reverts when dividing by zero.
    */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

// File: contracts\database.sol

contract database {

    /* libraries */
    using SafeMath for uint256;

    /* struct declarations */
    struct participant {
        address eth_address; // your eth address
        uint256 topl_address; // your topl address
        uint256 arbits; // the amount of a arbits you have
        uint256 num_of_pro_rata_tokens_alloted;
        bool arbits_kyc_whitelist; // if you pass arbits level kyc you get this
        uint8 num_of_uses;
    }

    /* variable declarations */
    // permission variables
    mapping(address => bool) public sale_owners;
    mapping(address => bool) public owners;
    mapping(address => bool) public masters;
    mapping(address => bool) public kycers;

    // database mapping
    mapping(address => participant) public participants;
    address[] public participant_keys;

    // sale open variables
    bool public arbits_presale_open = false; // Presale variables
    bool public iconiq_presale_open = false; // ^^^^^^^^^^^^^^^^^
    bool public arbits_sale_open = false; // Main sale variables

    // sale state variables
    uint256 public pre_kyc_bonus_denominator;
    uint256 public pre_kyc_bonus_numerator;
    uint256 public pre_kyc_iconiq_bonus_denominator;
    uint256 public pre_kyc_iconiq_bonus_numerator;

    uint256 public contrib_arbits_min;
    uint256 public contrib_arbits_max;

    // presale variables
    uint256 public presale_arbits_per_ether;        // two different prices, but same cap
    uint256 public presale_iconiq_arbits_per_ether; // and sold values
    uint256 public presale_arbits_total = 18000000;
    uint256 public presale_arbits_sold;

    // main sale variables
    uint256 public sale_arbits_per_ether;
    uint256 public sale_arbits_total;
    uint256 public sale_arbits_sold;

    /* constructor */
    constructor() public {
        owners[msg.sender] = true;
    }

    /* permission functions */
    function add_owner(address __subject) public only_owner {
        owners[__subject] = true;
    }

    function remove_owner(address __subject) public only_owner {
        owners[__subject] = false;
    }

    function add_master(address _subject) public only_owner {
        masters[_subject] = true;
    }

    function remove_master(address _subject) public only_owner {
        masters[_subject] = false;
    }

    function add_kycer(address _subject) public only_owner {
        kycers[_subject] = true;
    }

    function remove_kycer(address _subject) public only_owner {
        kycers[_subject] = false;
    }

    /* modifiers */
    modifier log_participant_update(address __eth_address) {
        participant_keys.push(__eth_address); // logs the given address in participant_keys
        _;
    }

    modifier only_owner() {
        require(owners[msg.sender]);
        _;
    }

    modifier only_kycer() {
        require(kycers[msg.sender]);
        _;
    }

    modifier only_master_or_owner() {
        require(masters[msg.sender] || owners[msg.sender]);
        _;
    }

    /* database functions */
    // GENERAL VARIABLE getters & setters
    // getters    
    function get_sale_owner(address _a) public view returns(bool) {
        return sale_owners[_a];
    }
    
    function get_contrib_arbits_min() public view returns(uint256) {
        return contrib_arbits_min;
    }

    function get_contrib_arbits_max() public view returns(uint256) {
        return contrib_arbits_max;
    }

    function get_pre_kyc_bonus_numerator() public view returns(uint256) {
        return pre_kyc_bonus_numerator;
    }

    function get_pre_kyc_bonus_denominator() public view returns(uint256) {
        return pre_kyc_bonus_denominator;
    }

    function get_pre_kyc_iconiq_bonus_numerator() public view returns(uint256) {
        return pre_kyc_iconiq_bonus_numerator;
    }

    function get_pre_kyc_iconiq_bonus_denominator() public view returns(uint256) {
        return pre_kyc_iconiq_bonus_denominator;
    }

    function get_presale_iconiq_arbits_per_ether() public view returns(uint256) {
        return (presale_iconiq_arbits_per_ether);
    }

    function get_presale_arbits_per_ether() public view returns(uint256) {
        return (presale_arbits_per_ether);
    }

    function get_presale_arbits_total() public view returns(uint256) {
        return (presale_arbits_total);
    }

    function get_presale_arbits_sold() public view returns(uint256) {
        return (presale_arbits_sold);
    }

    function get_sale_arbits_per_ether() public view returns(uint256) {
        return (sale_arbits_per_ether);
    }

    function get_sale_arbits_total() public view returns(uint256) {
        return (sale_arbits_total);
    }

    function get_sale_arbits_sold() public view returns(uint256) {
        return (sale_arbits_sold);
    }

    // setters
    function set_sale_owner(address _a, bool _v) public only_master_or_owner {
        sale_owners[_a] = _v;
    }

    function set_contrib_arbits_min(uint256 _v) public only_master_or_owner {
        contrib_arbits_min = _v;
    }

    function set_contrib_arbits_max(uint256 _v) public only_master_or_owner {
        contrib_arbits_max = _v;
    }

    function set_pre_kyc_bonus_numerator(uint256 _v) public only_master_or_owner {
        pre_kyc_bonus_numerator = _v;
    }

    function set_pre_kyc_bonus_denominator(uint256 _v) public only_master_or_owner {
        pre_kyc_bonus_denominator = _v;
    }

    function set_pre_kyc_iconiq_bonus_numerator(uint256 _v) public only_master_or_owner {
        pre_kyc_iconiq_bonus_numerator = _v;
    }

    function set_pre_kyc_iconiq_bonus_denominator(uint256 _v) public only_master_or_owner {
        pre_kyc_iconiq_bonus_denominator = _v;
    }

    function set_presale_iconiq_arbits_per_ether(uint256 _v) public only_master_or_owner {
        presale_iconiq_arbits_per_ether = _v;
    }

    function set_presale_arbits_per_ether(uint256 _v) public only_master_or_owner {
        presale_arbits_per_ether = _v;
    }

    function set_presale_arbits_total(uint256 _v) public only_master_or_owner {
        presale_arbits_total = _v;
    }

    function set_presale_arbits_sold(uint256 _v) public only_master_or_owner {
        presale_arbits_sold = _v;
    }

    function set_sale_arbits_per_ether(uint256 _v) public only_master_or_owner {
        sale_arbits_per_ether = _v;
    }

    function set_sale_arbits_total(uint256 _v) public only_master_or_owner {
        sale_arbits_total = _v;
    }

    function set_sale_arbits_sold(uint256 _v) public only_master_or_owner {
        sale_arbits_sold = _v;
    }

    // PARTICIPANT SPECIFIC getters and setters
    // getters
    function get_participant(address _a) public view returns(
        address,
        uint256,
        uint256,
        uint256,
        bool,
        uint8
    ) {
        participant storage subject = participants[_a];
        return (
            subject.eth_address,
            subject.topl_address,
            subject.arbits,
            subject.num_of_pro_rata_tokens_alloted,
            subject.arbits_kyc_whitelist,
            subject.num_of_uses
        );
    }

    function get_participant_num_of_uses(address _a) public view returns(uint8) {
        return (participants[_a].num_of_uses);
    }

    function get_participant_topl_address(address _a) public view returns(uint256) {
        return (participants[_a].topl_address);
    }

    function get_participant_arbits(address _a) public view returns(uint256) {
        return (participants[_a].arbits);
    }

    function get_participant_num_of_pro_rata_tokens_alloted(address _a) public view returns(uint256) {
        return (participants[_a].num_of_pro_rata_tokens_alloted);
    }

    function get_participant_arbits_kyc_whitelist(address _a) public view returns(bool) {
        return (participants[_a].arbits_kyc_whitelist);
    }

    // setters
    function set_participant(
        address _a,
        uint256 _ta,
        uint256 _arbits,
        uint256 _prta,
        bool _v3,
        uint8 _nou
    ) public only_master_or_owner log_participant_update(_a) {
        participant storage subject = participants[_a];
        subject.eth_address = _a;
        subject.topl_address = _ta;
        subject.arbits = _arbits;
        subject.num_of_pro_rata_tokens_alloted = _prta;
        subject.arbits_kyc_whitelist = _v3;
        subject.num_of_uses = _nou;
    }

    function set_participant_num_of_uses(
        address _a,
        uint8 _v
    ) public only_master_or_owner log_participant_update(_a) {
        participants[_a].num_of_uses = _v;
    }

    function set_participant_topl_address(
        address _a,
        uint256 _ta
    ) public only_master_or_owner log_participant_update(_a) {
        participants[_a].topl_address = _ta;
    }

    function set_participant_arbits(
        address _a,
        uint256 _v
    ) public only_master_or_owner log_participant_update(_a) {
        participants[_a].arbits = _v;
    }

    function set_participant_num_of_pro_rata_tokens_alloted(
        address _a,
        uint256 _v
    ) public only_master_or_owner log_participant_update(_a) {
        participants[_a].num_of_pro_rata_tokens_alloted = _v;
    }

    function set_participant_arbits_kyc_whitelist(
        address _a,
        bool _v
    ) public only_kycer log_participant_update(_a) {
        participants[_a].arbits_kyc_whitelist = _v;
    }


    //
    // STATE FLAG FUNCTIONS: Getter, setter, and toggling functions for state flags.

    // GETTERS
    function get_iconiq_presale_open() public view only_master_or_owner returns(bool) {
        return iconiq_presale_open;
    }

    function get_arbits_presale_open() public view only_master_or_owner returns(bool) {
        return arbits_presale_open;
    }

    function get_arbits_sale_open() public view only_master_or_owner returns(bool) {
        return arbits_sale_open;
    }

    // SETTERS
    function set_iconiq_presale_open(bool _v) public only_master_or_owner {
        iconiq_presale_open = _v;
    }

    function set_arbits_presale_open(bool _v) public only_master_or_owner {
        arbits_presale_open = _v;
    }

    function set_arbits_sale_open(bool _v) public only_master_or_owner {
        arbits_sale_open = _v;
    }

}

// File: contracts\topl_database_lib.sol

// This library serves as an wrapper to the database.sol contract

library topl_database_lib {

    //// PARTICIPANT SPECIFIC FUNCTIONS
    // getters
    function get_participant(address db, address _a) internal view returns(
        address,
        uint256,
        uint256,
        uint256,
        bool,
        uint8
    ) {
        return database(db).get_participant(_a);
    }

    function get_topl_address(address db, address _a) internal view returns(uint256) {
        return database(db).get_participant_topl_address(_a);
    }

    function get_arbits(address db, address _a) internal view returns(uint256) {
        return database(db).get_participant_arbits(_a);
    }

    function get_iconiq_tokens(address db, address _a) internal view returns(uint256) {
        return database(db).get_participant_num_of_pro_rata_tokens_alloted(_a);
    }

    function get_arbits_whitelist(address db, address _a) internal view returns(bool) {
        return database(db).get_participant_arbits_kyc_whitelist(_a);
    }

    function get_num_of_uses(address db, address _a) internal view returns(uint8) {
        return database(db).get_participant_num_of_uses(_a);
    }

    // setters
    function set_participant(
        address db,
        address _a,
        uint256 _ta,
        uint256 _arbits,
        uint256 _prta,
        bool _v3,
        uint8 _nou
    ) internal {
        database(db).set_participant(_a, _ta, _arbits, _prta, _v3, _nou);
        emit e_set_participant(_a, _ta, _arbits, _prta, _v3, _nou);
    }

    function set_topl_address(address db, address _a, uint256 _ta) internal {
        database(db).set_participant_topl_address(_a, _ta);
        emit e_set_topl_address(_a, _ta);
    }

    function set_arbits(address db, address _a, uint256 _v) internal {
        database(db).set_participant_arbits(_a, _v);
        emit e_set_arbits(_a, _v);
    }

    function set_iconiq_tokens(address db, address _a, uint256 _v) internal {
        database(db).set_participant_num_of_pro_rata_tokens_alloted(_a, _v);
        emit e_set_iconiq_tokens(_a, _v);
    }

    function set_arbits_whitelist(address db, address _a, bool _v) internal {
        database(db).set_participant_arbits_kyc_whitelist(_a, _v);
        emit e_set_arbits_whitelist(_a, _v);
    }

    function set_num_of_uses(address db, address _a, uint8 _v) internal {
        database(db).set_participant_num_of_uses(_a, _v);
        emit e_set_num_of_uses(_a, _v);
    }

    // modifiers
    function add_arbits(address db, address _a, uint256 _v) internal {
        uint256 c = database(db).get_participant_arbits(_a) + _v;     // safe math check
        assert(c >= database(db).get_participant_arbits(_a)); //
        database(db).set_participant_arbits(
            _a,
            (database(db).get_participant_arbits(_a) + _v)
        );
        emit e_add_arbits(_a, _v);
    }

    function sub_arbits(address db, address _a, uint256 _v) internal {
        assert(_v <= database(db).get_participant_arbits(_a)); // safe math check
        database(db).set_participant_arbits(
            _a,
            (database(db).get_participant_arbits(_a) - _v)
        );
        emit e_sub_arbits(_a, _v);
    }

    //// ICONIQ SALE SPECIFIC FUNCTIONS
    // getters
    function get_pre_kyc_iconiq_bonus_numerator(address db) internal view returns(uint256) {
        return database(db).get_pre_kyc_iconiq_bonus_numerator();
    }

    function get_pre_kyc_iconiq_bonus_denominator(address db) internal view returns(uint256) {
        return database(db).get_pre_kyc_iconiq_bonus_denominator();
    }

    function get_iconiq_presale_open(address db) internal view returns(bool) {
        return database(db).get_iconiq_presale_open();
    }

    function get_presale_iconiq_arbits_per_ether(address db) internal view returns(uint256) {
        return database(db).get_presale_iconiq_arbits_per_ether();
    }

    // setters
    function set_pre_kyc_iconiq_bonus_numerator(address db, uint256 _v) internal {
        database(db).set_pre_kyc_iconiq_bonus_numerator(_v);
        emit e_set_pre_kyc_iconiq_bonus_numerator(_v);
    }

    function set_pre_kyc_iconiq_bonus_denominator(address db, uint256 _v) internal {
        database(db).set_pre_kyc_iconiq_bonus_denominator(_v);
        emit e_set_pre_kyc_iconiq_bonus_denominator(_v);
    }

    function set_iconiq_presale_open(address db, bool _v) internal {
        database(db).set_iconiq_presale_open(_v);
        emit e_set_iconiq_presale_open(_v);
    }

    function set_presale_iconiq_arbits_per_ether(address db, uint256 _v) internal {
        database(db).set_presale_iconiq_arbits_per_ether(_v);
        emit e_set_presale_iconiq_arbits_per_ether(_v);
    }

    //// PUBLIC PRESALE SPECIFIC FUNCTIONS (arbit_presale)
    // getters
    function get_pre_kyc_bonus_numerator(address db) internal view returns(uint256) {
        return database(db).get_pre_kyc_bonus_numerator();
    }

    function get_pre_kyc_bonus_denominator(address db) internal view returns(uint256) {
        return database(db).get_pre_kyc_bonus_denominator();
    }

    function get_arbits_presale_open(address db) internal view returns(bool) {
        return database(db).get_arbits_presale_open();
    }

    function get_presale_arbits_per_ether(address db) internal view returns(uint256) {
        return database(db).get_presale_arbits_per_ether();
    }

    // setters
    function set_pre_kyc_bonus_numerator(address db, uint256 _v) internal {
        database(db).set_pre_kyc_bonus_numerator(_v);
        emit e_set_pre_kyc_bonus_numerator(_v);
    }

    function set_pre_kyc_bonus_denominator(address db, uint256 _v) internal {
        database(db).set_pre_kyc_bonus_denominator(_v);
        emit e_set_pre_kyc_bonus_denominator(_v);
    }

    function set_arbits_presale_open(address db, bool _v) internal {
        database(db).set_arbits_presale_open(_v);
        emit e_set_arbits_presale_open(_v);
    }

    // this function is not strictly only used by arbit_presale since it is used for rollover
    // when an iconiq member goes over their allotment.
    function set_presale_arbits_per_ether(address db, uint256 _v) internal {
        database(db).set_presale_arbits_per_ether(_v);
        emit e_set_presale_arbits_per_ether(_v);
    }

    //// "GLOABL" SALE FUNCTIONS (applies across the entire presale)
    // getters
    function get_presale_arbits_total(address db) internal view returns(uint256) {
        return database(db).get_presale_arbits_total();
    }

    function get_presale_arbits_sold(address db) internal view returns(uint256) {
        return database(db).get_presale_arbits_sold();
    }

    function get_arbits_max_contribution(address db) internal view returns(uint256) {
        return database(db).get_contrib_arbits_max();
    }

    function get_arbits_min_contribution(address db) internal view returns(uint256) {
        return database(db).get_contrib_arbits_min();
    }

    // setters
    function set_presale_arbits_total(address db, uint256 _v) internal {
        database(db).set_presale_arbits_total(_v);
        emit e_set_presale_arbits_total(_v);
    }

    function set_presale_arbits_sold(address db, uint256 _v) internal {
        database(db).set_presale_arbits_sold(_v);
        emit e_set_presale_arbits_sold(_v);
    }

    function set_arbits_max_contribution(address db, uint256 _v) internal {
        database(db).set_contrib_arbits_max(_v);
        emit e_set_arbits_max_contribution(_v);
    }

    function set_arbits_min_contribution(address db, uint256 _v) internal {
        database(db).set_contrib_arbits_min(_v);
        emit e_set_arbits_min_contribution(_v);
    }

    // modifiers
    function add_presale_arbits_sold(address db, uint256 _v) internal {
        uint256 c = database(db).get_presale_arbits_sold() + _v;     // safe math check
        assert(c >= database(db).get_presale_arbits_sold()); //
        database(db).set_presale_arbits_sold(
            (database(db).get_presale_arbits_sold() + _v)
        );
        emit e_add_presale_arbits_sold(_v);
    }

    function sub_presale_arbits_sold(address db, uint256 _v) internal {
        assert(_v <= database(db).get_presale_arbits_sold()); // safe math check
        database(db).set_presale_arbits_sold(
            (database(db).get_presale_arbits_sold() - _v)
        );
        emit e_sub_presale_arbits_sold(_v);
    }
    
    function set_sale_owner(address db, address _a, bool _v) internal {
        database(db).set_sale_owner(_a, _v);
    }

    function get_sale_owner(address db, address _a) internal view returns(bool) {
        return database(db).get_sale_owner(_a);
    }

    event e_set_sale_owner(address, bool);
    event e_set_num_of_uses(address, uint8);
    event e_set_arbits_whitelist(address, bool);
    event e_set_participant(address, uint256, uint256, uint256, bool, uint8);
    event e_set_topl_address(address, uint256);
    event e_set_arbits(address, uint256);
    event e_set_iconiq_tokens(address, uint256);
    event e_add_arbits(address, uint256);
    event e_sub_arbits(address, uint256);
    event e_set_pre_kyc_bonus_numerator(uint256);
    event e_set_pre_kyc_bonus_denominator(uint256);
    event e_set_iconiq_presale_open(bool);
    event e_set_arbits_presale_open(bool);
    event e_set_presale_iconiq_arbits_per_ether(uint256);
    event e_set_presale_arbits_per_ether(uint256);
    event e_set_presale_arbits_total(uint256);
    event e_set_presale_arbits_sold(uint256);
    event e_add_presale_arbits_sold(uint256);
    event e_sub_presale_arbits_sold(uint256);
    event e_set_arbits_max_contribution(uint256);
    event e_set_arbits_min_contribution(uint256);
    event e_set_pre_kyc_iconiq_bonus_numerator(uint256);
    event e_set_pre_kyc_iconiq_bonus_denominator(uint256);
}

// File: contracts\arbits_presale.sol

contract arbits_presale {

    // libraries
    using topl_database_lib for address;
    using SafeMath for uint256;

    // contract level vars
    address public owner;
    address public db;


    // helpful data structs
    struct participant {
        address eth_address; // your eth address
        uint256 topl_address; // your topl address
        uint256 arbits; // the amount of a arbits you have
        uint256 num_of_pro_rata_tokens_alloted;
        bool arbits_kyc_whitelist; // if you pass arbits level kyc you get this
        uint8 num_of_uses;
    }

    // permissions
    constructor(address __db) public {
        db = __db;
        owner = msg.sender;
    }

    function owner_linkage() public { // must be called after the sale contract has been linked to the database contract via database&#39;s add master function
        db.set_sale_owner(owner, true);
    }

    modifier only_owner() {
        require(db.get_sale_owner(msg.sender));
        _;
    }

    function add_owner(address __subject) public only_owner {
        db.set_sale_owner(__subject, true);
        emit e_add_owner(msg.sender, __subject);
    }

    function remove_owner(address __subject) public only_owner {
        db.set_sale_owner(__subject, false);
        emit e_remove_owner(msg.sender, __subject);
    }

    // general modifiers
    modifier presale_open() {
        require(db.get_arbits_presale_open());
        _;
    }

    modifier use_count() {
        uint8 uses = db.get_num_of_uses(msg.sender);
        require(uses < 5);
        db.set_num_of_uses(msg.sender, uses + 1);
        _;
    }

    // functionality
    function participate_in_arbits_presale_crypto() public payable presale_open use_count {
        /////////////////////////////////////////////////////////////////////
                                                                           //
        (                                                                  //
            address p1,                                                    //
            uint256 p2,                                                    // LOAD
            uint256 p3,                                                    // PARTICIPANT
            uint256 p4,                                                    // DATA
            bool p5,                                                       // FROM
            uint8 p6                                                       // DATABASE
        ) = db.get_participant(msg.sender);                                //
        participant memory subject = participant(p1, p2, p3, p4, p5, p6);  //
                                                                           //
        /////////////////////////////////////////////////////////////////////

        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                                                                                                          //
        uint256 subject_tokens_to_add = msg.value.mul(db.get_presale_arbits_per_ether()).div(1 ether);                                    //
        if (subject.arbits_kyc_whitelist) {                                                                                               // Arbits
            subject_tokens_to_add = subject_tokens_to_add.mul(db.get_pre_kyc_bonus_numerator()).div(db.get_pre_kyc_bonus_denominator());  // Purchased
        }                                                                                                                                 // Calculation
                                                                                                                                          //
        ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

        // Note: users must send ether in amounts that are evenly divide tokens_per_ether.
        // Ex: If tokens_per_ether = 4 and a user sends .9 ether they will receive 3 tokens and forfeit .15 ether.
        // The correct interaction would be to send some increment of .25 ether.

        //////////////////////////////////////////////////////////////////////////////////////////////////////
                                                                                                            //
        require(db.get_presale_arbits_total() >= db.get_presale_arbits_sold().add(subject_tokens_to_add));  // Sale
        require(db.get_arbits_max_contribution() >= subject_tokens_to_add); // max                          // Limit
        require(db.get_arbits_min_contribution() <= subject_tokens_to_add); // min                          // Checks
                                                                                                            //
        //////////////////////////////////////////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////////////////////////////////
                                                                                   //
        db.add_presale_arbits_sold(subject_tokens_to_add); // update sold counter  // Update
        db.add_arbits(msg.sender, subject_tokens_to_add); // update arbits         // Database
                                                                                   //
        /////////////////////////////////////////////////////////////////////////////

        ///////////////////////////////////////////////////////////////////////
                                                                             //
        emit e_participate_in_arbits_presale_crypto(msg.sender, msg.value);  // Event
                                                                             //
        ///////////////////////////////////////////////////////////////////////
    }

    function participate_in_arbits_presale_fiat(address _a, uint256 _t) public only_owner {
        //////////////////////////////////////////////////////////
                                                                //
        db.add_presale_arbits_sold(_t); // update sold counter  // Update
        db.add_arbits(_a, _t); // update arbits                 // Database
                                                                //
        //////////////////////////////////////////////////////////

        //////////////////////////////////////////////////////
                                                            //
        emit e_participate_in_arbits_presale_fiat(_a, _t);  // Event
                                                            //
        //////////////////////////////////////////////////////
    }

    function() public payable {
        participate_in_arbits_presale_crypto(); // allows users to participate without an explicit function call
        emit e_fallback(msg.sender, msg.value);
    }

    // owner withdrawals
    function kill_and_withdraw(address withdraw_to) public only_owner {
        emit e_kill_and_withdraw(withdraw_to);
        selfdestruct(withdraw_to);
    }

    function withdraw_some_amount(address withdraw_to, uint256 amount) public only_owner {
        withdraw_to.transfer(amount); // amount in wei, throws if error
        emit e_withdraw_some_amount(withdraw_to, amount);
    }

    // arbit specific sale settings
    function set_sale_open() public only_owner {
        require(db.get_presale_arbits_per_ether() > 0);
        require(db.get_arbits_max_contribution() > 0);
        require(db.get_arbits_min_contribution() > 0);
        require(db.get_pre_kyc_bonus_numerator() > 0);
        require(db.get_pre_kyc_bonus_denominator() > 0);
        db.set_arbits_presale_open(true);
    }

    function set_sale_closed() public only_owner {
        db.set_arbits_presale_open(false);
    }

    function set_tokens_per_ether(uint256 _v) public only_owner {
        db.set_presale_arbits_per_ether(_v);
    }

    function set_pre_kyc_bonus_numerator(uint256 _v) public only_owner {
        db.set_pre_kyc_bonus_numerator(_v);
    }

    function set_pre_kyc_bonus_denominator(uint256 _v) public only_owner {
        db.set_pre_kyc_bonus_denominator(_v);
    }

    //// This section provides external functionality for modifying the database 
    // whitelist
    function add_to_whitelist(address _a) public only_owner {
        db.set_arbits_whitelist(_a, true);
        emit e_add_to_whitelist(msg.sender, _a);
    }

    function remove_from_whitelist(address _a) public only_owner {
        db.set_arbits_whitelist(_a, false);
        emit e_remove_from_whitelist(msg.sender, _a);
    }

    // general sale settings
    function set_max_contribution(uint256 _v) public only_owner {
        db.set_arbits_max_contribution(_v);
    }

    function set_min_contribution(uint256 _v) public only_owner {
        db.set_arbits_min_contribution(_v);
    }

    function set_tokens_total(uint256 _v) public only_owner {
        db.set_presale_arbits_total(_v);
    }

    function set_tokens_sold(uint256 _v) public only_owner {
        db.set_presale_arbits_sold(_v);
    }

    // helpers
    function is_presale_open() public view returns(bool) {
        return db.get_arbits_presale_open();
    }

    function am_i_on_the_whitelist() public view returns(bool) {
        return db.get_arbits_whitelist(msg.sender);
    }

    function how_many_arbits_do_i_have() public view returns(uint256) {
        return db.get_arbits(msg.sender);
    }

    // events
    //
    // All storage calls are logged via events emitted in the library functions.
    // Because web3 bugs out when when libraries call events that aren&#39;t defined in
    // the parent contract. We redefine them here.
    //
    // contract level events
    event e_add_owner(address addres1, address address2); // adder, addie <-------- These are words now!
    event e_remove_owner(address addres1, address address2); // remover, removie <_/
    event e_add_to_whitelist(address, address); // adder, addie
    event e_remove_from_whitelist(address, address); // remover, removie
    event e_participate_in_arbits_presale_fiat(address, uint256); // person getting arbits, number of arbits
    event e_participate_in_arbits_presale_crypto(address, uint256); // msg.sender, msg.value
    event e_fallback(address, uint256); // msg.sender, msg.value (used to gather data on what %
    // of people just send ether vs sending a function call
    event e_kill_and_withdraw(address); // person that just took all our money
    event e_withdraw_some_amount(address, uint256); // withdrawal address, amount withdrawn
}