pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";
import "openzeppelin-solidity/contracts/token/ERC20/DetailedERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./LeasedEmblem.sol";

contract Emblem is DetailedERC20, StandardToken, Ownable {
  using SafeMath for uint256;

   mapping (bytes12 => address) public vanityAddresses;
   mapping (address => bytes12[]) public ownedVanities;
   mapping (address => mapping(bytes12 => uint256)) public ownedVanitiesIndex;
   mapping (bytes12 => uint256) allVanitiesIndex;
   bytes12[] public allVanities;
   mapping (address => mapping (bytes12 => address)) internal allowedVanities;

   mapping (bytes12 => uint256) vanityFees;
   mapping (bytes12 => bool) vanityFeeEnabled;

   bool internal useVanityFees = true;
   uint256 internal vanityPurchaseCost = 100 * (10 ** 8);

   mapping (address => bool) public frozenAccounts;
   bool public completeFreeze = false;

   mapping (address => bool) internal freezable;
   mapping (address => bool) internal externalFreezers;

   address leaseExchange;
   LeasedEmblem LEMB;

   event TransferVanity(address from, address to, bytes12 vanity);
   event ApprovedVanity(address from, address to, bytes12 vanity);
   event VanityPurchased(address from, bytes12 vanity);

   constructor(string _name, string _ticker, uint8 _decimal, uint256 _supply, address _wallet, address _lemb) DetailedERC20(_name, _ticker, _decimal) public {
     totalSupply_ = _supply;
     balances[_wallet] = _supply;
     LEMB = LeasedEmblem(_lemb);
   }

   function setLeaseExchange(address _leaseExchange) public onlyOwner {
     leaseExchange = _leaseExchange;
   }

   function setVanityPurchaseCost(uint256 cost) public onlyOwner {
     vanityPurchaseCost = cost;
   }

   function enableFees(bool enabled) public onlyOwner {
     useVanityFees = enabled;
   }

   function setLEMB(address _lemb) public onlyOwner {
     LEMB = LeasedEmblem(_lemb);
   }

   function setVanityFee(bytes12 vanity, uint256 fee) public onlyOwner {
     require(fee >= 0);
     vanityFees[vanity] = fee;
   }

   function getFee(bytes12 vanity) public view returns(uint256) {
     return vanityFees[vanity];
   }

   function enabledVanityFee(bytes12 vanity) public view returns(bool) {
     return vanityFeeEnabled[vanity] && useVanityFees;
   }

   function setTicker(string _ticker) public onlyOwner {
     symbol = _ticker;
   }

   function approveOwner(uint256 _value) public onlyOwner returns (bool) {
     allowed[msg.sender][address(this)] = _value;
     return true;
   }

   function vanityAllowance(address _owner, bytes12 _vanity, address _spender) public view returns (bool) {
     return allowedVanities[_owner][_vanity] == _spender;
   }

   function getVanityOwner(bytes12 _vanity) public view returns (address) {
     return vanityAddresses[_vanity];
   }

   function getAllVanities() public view returns (bytes12[]){
     return allVanities;
   }

   function getMyVanities() public view returns (bytes12[]){
     return ownedVanities[msg.sender];
   }

   function approveVanity(address _spender, bytes12 _vanity) public returns (bool) {
     require(vanityAddresses[_vanity] == msg.sender);
     allowedVanities[msg.sender][_vanity] = _spender;

     emit ApprovedVanity(msg.sender, _spender, _vanity);
     return true;
   }

   function clearVanityApproval(bytes12 _vanity) public returns (bool){
     require(vanityAddresses[_vanity] == msg.sender);
     delete allowedVanities[msg.sender][_vanity];
     return true;
   }

   function transferVanity(bytes12 van, address newOwner) public returns (bool) {
     require(newOwner != 0x0);
     require(vanityAddresses[van] == msg.sender);

     vanityAddresses[van] = newOwner;
     ownedVanities[newOwner].push(van);
     ownedVanitiesIndex[newOwner][van] = ownedVanities[newOwner].length.sub(1);

     uint256 vanityIndex = ownedVanitiesIndex[msg.sender][van];
     uint256 lastVanityIndex = ownedVanities[msg.sender].length.sub(1);
     bytes12 lastVanity = ownedVanities[msg.sender][lastVanityIndex];

     ownedVanities[msg.sender][vanityIndex] = lastVanity;
     ownedVanities[msg.sender][lastVanityIndex] = "";
     ownedVanities[msg.sender].length--;

     ownedVanitiesIndex[msg.sender][van] = 0;
     ownedVanitiesIndex[msg.sender][lastVanity] = vanityIndex;

     emit TransferVanity(msg.sender, newOwner,van);

     return true;
   }

   function transferVanityFrom(
     address _from,
     address _to,
     bytes12 _vanity
   )
     public
     returns (bool)
   {
     require(_to != address(0));
     require(_from == vanityAddresses[_vanity]);
     require(msg.sender == allowedVanities[_from][_vanity]);

     vanityAddresses[_vanity] = _to;
     ownedVanities[_to].push(_vanity);
     ownedVanitiesIndex[_to][_vanity] = ownedVanities[_to].length.sub(1);

     uint256 vanityIndex = ownedVanitiesIndex[_from][_vanity];
     uint256 lastVanityIndex = ownedVanities[_from].length.sub(1);
     bytes12 lastVanity = ownedVanities[_from][lastVanityIndex];

     ownedVanities[_from][vanityIndex] = lastVanity;
     ownedVanities[_from][lastVanityIndex] = "";
     ownedVanities[_from].length--;

     ownedVanitiesIndex[_from][_vanity] = 0;
     ownedVanitiesIndex[_from][lastVanity] = vanityIndex;

     emit TransferVanity(msg.sender, _to,_vanity);

     return true;
   }

   function purchaseVanity(bytes12 van) public returns (bool) {
     require(vanityAddresses[van] == address(0));

     for(uint8 i = 0; i < 12; i++){
       require((van[i] >= 48 && van[i] <= 57) || (van[i] >= 65 && van[i] <= 90));
     }

     require(canTransfer(msg.sender,vanityPurchaseCost));

     balances[msg.sender] = balances[msg.sender].sub(vanityPurchaseCost);
     balances[address(this)] = balances[address(this)].add(vanityPurchaseCost);
     emit Transfer(msg.sender, address(this), vanityPurchaseCost);

     vanityAddresses[van] = msg.sender;
     ownedVanities[msg.sender].push(van);
     ownedVanitiesIndex[msg.sender][van] = ownedVanities[msg.sender].length.sub(1);
     allVanities.push(van);
     allVanitiesIndex[van] = allVanities.length.sub(1);

     emit VanityPurchased(msg.sender, van);
   }

   function freezeTransfers(bool _freeze) public onlyOwner {
     completeFreeze = _freeze;
   }

   function freezeAccount(address _target, bool _freeze) public onlyOwner {
     frozenAccounts[_target] = _freeze;
   }

   function canTransfer(address _account,uint256 _value) internal view returns (bool) {
      return (!frozenAccounts[_account] && !completeFreeze && (_value + LEMB.getAmountForUserMining(_account) <= balances[_account]));
   }

   function transfer(address _to, uint256 _value) public returns (bool){
      require(canTransfer(msg.sender,_value));
      super.transfer(_to,_value);
   }

   function multiTransfer(bytes32[] _addressesAndAmounts) public {
      for (uint i = 0; i < _addressesAndAmounts.length; i++) {
          address to = address(_addressesAndAmounts[i] >> 96);
          uint amount = uint(uint56(_addressesAndAmounts[i]));
          transfer(to, amount);
      }
   }

   function freezeMe(bool freeze) public {
     require(!frozenAccounts[msg.sender]);
     freezable[msg.sender] = freeze;
   }

   function canFreeze(address _target) public view returns(bool){
     return freezable[_target];
   }

   function isFrozen(address _target) public view returns(bool) {
     return completeFreeze || frozenAccounts[_target];
   }

   function externalFreezeAccount(address _target, bool _freeze) public {
     require(freezable[_target]);
     require(externalFreezers[msg.sender]);
     frozenAccounts[_target] = _freeze;
   }

   function setExternalFreezer(address _target, bool _canFreeze) public onlyOwner {
     externalFreezers[_target] = _canFreeze;
   }


   function transferFrom(address _from, address _to, uint256 _value) public returns (bool){
      require(!completeFreeze);
      if(msg.sender != leaseExchange) require(canTransfer(_from,_value));
      super.transferFrom(_from,_to,_value);
   }

   function decreaseApproval(address _spender,uint256 _subtractedValue) public returns (bool) {


     if(_spender == leaseExchange) {
       require(allowed[msg.sender][_spender].sub(_subtractedValue) >= LEMB.getAmountForUserMining(msg.sender));
     }
     super.decreaseApproval(_spender,_subtractedValue);
   }

   function approve(address _spender, uint256 _value) public returns (bool) {


     if(_spender == leaseExchange){
       require(_value >= LEMB.getAmountForUserMining(msg.sender));
     }

     allowed[msg.sender][_spender] = _value;
     emit Approval(msg.sender, _spender, _value);
     return true;
   }

}
