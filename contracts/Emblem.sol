// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./LeasedEmblem.sol";

contract Emblem is ERC20, ERC20Capped, Ownable {
  using SafeMath for uint256;

   bool internal useVanityFees;
   address internal leaseExchange;
   address internal vanityPurchaseReceiver;
   uint256 internal vanityPurchaseCost = 1 * (10 ** 8); //1 EMB
   bytes12[] internal allVanities;
   LeasedEmblem internal LEMB;

   mapping (bytes12 => address) public vanityAddresses;
   mapping (address => bytes12[]) public ownedVanities;
   mapping (address => mapping(bytes12 => uint256)) public ownedVanitiesIndex;
   mapping (bytes12 => uint256) internal allVanitiesIndex;
   mapping (address => mapping (bytes12 => address)) internal allowedVanities;
   mapping (bytes12 => uint256) internal vanityFees;

   event TransferVanity(address indexed from, address indexed to, bytes12 vanity);
   event ApprovedVanity(address indexed from, address indexed to, bytes12 vanity);
   event VanityPurchaseCost(uint256 cost);
   event VanityPurchased(address indexed from, bytes12 vanity);

   constructor(string memory _name, string memory _ticker, uint8 _decimal, uint256 _supply, address _wallet) public ERC20(_name, _ticker) ERC20Capped(_supply) {
     _mint(_wallet,_supply);
     _setupDecimals(_decimal);
   }

   function setLeaseExchange(address _leaseExchange) public onlyOwner {
     require(_leaseExchange != address(0), "Lease Exchange address cannot be set to 0");
     leaseExchange = _leaseExchange;
   }

   function setVanityPurchaseCost(uint256 cost) public onlyOwner {
     require(cost > 0, "Vanity Purchase Cost must be > 0");
     vanityPurchaseCost = cost;
     emit VanityPurchaseCost(cost);
   }

   function getVanityPurchaseCost() public view returns (uint256) {
     return vanityPurchaseCost;
   }

   function enableFees(bool enabled) public onlyOwner {
     useVanityFees = enabled;
   }

   function setVanityPurchaseReceiver(address _address) public onlyOwner {
     require(_address != address(0), "Vanity Purchase Receiver address cannot be set to 0");
     vanityPurchaseReceiver = _address;
   }

   function setLEMB(address _lemb) public onlyOwner {
     require(_lemb != address(0), "Leased Emblem address cannot be set to 0");
     LEMB = LeasedEmblem(_lemb);
   }

   function setVanityFee(bytes12 vanity, uint256 fee) public onlyOwner {
     vanityFees[vanity] = fee;
   }

   function getFee(bytes12 vanity) public view returns(uint256) {
     return vanityFees[vanity];
   }

   function enabledVanityFee() public view returns(bool) {
     return useVanityFees;
   }

   function vanityAllowance(address _owner, bytes12 _vanity, address _spender) public view returns (bool) {
     return allowedVanities[_owner][_vanity] == _spender;
   }

   function getVanityOwner(bytes12 _vanity) public view returns (address) {
     return vanityAddresses[_vanity];
   }

   function getAllVanities() public view returns (bytes12[] memory){
     return allVanities;
   }

   function getMyVanities() public view returns (bytes12[] memory){
     return ownedVanities[msg.sender];
   }

   function approveVanity(address _spender, bytes12 _vanity) public returns (bool) {
     require(_spender != address(0), 'spender of vanity cannot be address zero');
     require(vanityAddresses[_vanity] == msg.sender, 'transaction initiator must own the vanity');
     allowedVanities[msg.sender][_vanity] = _spender;

     emit ApprovedVanity(msg.sender, _spender, _vanity);
     return true;
   }

   function clearVanityApproval(bytes12 _vanity) public returns (bool){
     require(vanityAddresses[_vanity] == msg.sender,'transaction initiator must own the vanity');
     delete allowedVanities[msg.sender][_vanity];
     return true;
   }

   function transferVanity(bytes12 van, address newOwner) public returns (bool) {
     require(newOwner != address(0),'new vanity owner cannot be of address zero');
     require(vanityAddresses[van] == msg.sender,'transaction initiator must own the vanity');

     vanityAddresses[van] = newOwner;
     ownedVanities[newOwner].push(van);
     ownedVanitiesIndex[newOwner][van] = ownedVanities[newOwner].length.sub(1);

     uint256 vanityIndex = ownedVanitiesIndex[msg.sender][van];
     uint256 lastVanityIndex = ownedVanities[msg.sender].length.sub(1);
     bytes12 lastVanity = ownedVanities[msg.sender][lastVanityIndex];

     ownedVanities[msg.sender][vanityIndex] = lastVanity;
     ownedVanities[msg.sender].pop();

     delete ownedVanitiesIndex[msg.sender][van];
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
     require(_to != address(0),'new vanity owner cannot be of address zero');
     require(_from == vanityAddresses[_vanity],'the vanity being transferred must be owned by address _from');
     require(msg.sender == allowedVanities[_from][_vanity],'transaction initiator must be approved to transfer vanity');

     vanityAddresses[_vanity] = _to;
     ownedVanities[_to].push(_vanity);
     ownedVanitiesIndex[_to][_vanity] = ownedVanities[_to].length.sub(1);

     uint256 vanityIndex = ownedVanitiesIndex[_from][_vanity];
     uint256 lastVanityIndex = ownedVanities[_from].length.sub(1);
     bytes12 lastVanity = ownedVanities[_from][lastVanityIndex];

     ownedVanities[_from][vanityIndex] = lastVanity;
     ownedVanities[_from].pop();

     delete ownedVanitiesIndex[_from][_vanity];
     ownedVanitiesIndex[_from][lastVanity] = vanityIndex;

     emit TransferVanity(_from, _to,_vanity);

     return true;
   }

   function purchaseVanity(bytes12 van) public returns (bool) {
     require(vanityPurchaseReceiver != address(0),'vanity purchase receiver must be set');
     require(vanityAddresses[van] == address(0),'vanity must not be purchased so far');

     for(uint8 i = 0; i < 12; i++){
       //Vanities must be lower case
       require((uint8(van[i]) >= 48 && uint8(van[i]) <= 57) || (uint8(van[i]) >= 65 && uint8(van[i]) <= 90));
     }
     if(vanityPurchaseCost > 0) this.transferFrom(msg.sender,vanityPurchaseReceiver, vanityPurchaseCost);

     vanityAddresses[van] = msg.sender;
     ownedVanities[msg.sender].push(van);
     ownedVanitiesIndex[msg.sender][van] = ownedVanities[msg.sender].length.sub(1);
     allVanities.push(van);
     allVanitiesIndex[van] = allVanities.length.sub(1);

     emit VanityPurchased(msg.sender, van);
     return true;
   }

   //ensure the amount being transferred does not dip into EMB owned through leases.
   function canTransfer(address _account,uint256 _value) internal view returns (bool) {
      if(address(LEMB)!= address(0)){
        require((_value.add(LEMB.getAmountForUserMining(_account)) <= balanceOf(_account)),'value being sent cannot dip into EMB acquired through leasing');
      }
      return true;
   }

   function transfer(address _to, uint256 _value) public override returns (bool){
      require(canTransfer(msg.sender,_value),'value must be transferrable by transaction initiator');
      super.transfer(_to,_value);
      return true;
   }

   function multiTransfer(bytes27[] calldata _addressesAndAmounts) external returns (bool){
      for (uint i = 0; i < _addressesAndAmounts.length; i++) {
          address to = address(uint216(_addressesAndAmounts[i] >> 56));
          uint216 amount = uint216((_addressesAndAmounts[i] << 160) >> 160);
          transfer(to, amount);
      }
      return true;
   }

   function releaseEMB(address _from, address _to, uint256 _value) external returns (bool){
     require(address(0) != leaseExchange, 'Lease Exchange must be activated');
     require(msg.sender == leaseExchange, 'only the lease exchange can call this function');
     transferFrom(_from,_to,_value);
     return true;
   }

   function transferFrom(address _from, address _to, uint256 _value) public override returns (bool){
      if(msg.sender != leaseExchange) require(canTransfer(_from,_value),'value must be transfered from address _from');
      super.transferFrom(_from,_to,_value);
      return true;
   }

   function decreaseAllowance(address _spender,uint256 _subtractedValue) public override returns (bool) {
     if(_spender == leaseExchange) {
       if(address(LEMB)!= address(0)){
         require(allowance(msg.sender,_spender).sub(_subtractedValue) >= LEMB.getAmountForUserMining(msg.sender),'if spender is the lease exchange, the allowance must be greater than the amount the user is mining with LEMB');
       }
     }
     super.decreaseAllowance(_spender,_subtractedValue);
     return true;
   }

   function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20, ERC20Capped) {
      super._beforeTokenTransfer(from, to, amount);

      if (from == address(0)) { // When minting tokens
          require(totalSupply().add(amount) <= cap(), "ERC20Capped: cap exceeded");
      }
    }

   function approve(address _spender, uint256 _value) public override returns (bool) {
     if(_spender == leaseExchange){
       if(address(LEMB)!= address(0)){
         require(_value >= LEMB.getAmountForUserMining(msg.sender));
       }
     }
     _approve(msg.sender, _spender, _value);
     return true;
   }

}
