// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract LeasedEmblem is ERC721, Ownable {
  using SafeMath for uint256;

  address internal leaseExchange;

  struct Metadata {
    uint256 amount;
    address leasor;
    uint256 expiry
    bool isMining;
  }

  mapping(uint256 => Metadata) public metadata;

  mapping(address => uint256[]) internal leasedTokens;

  mapping(uint256 => uint256) internal leasedTokensIndex;

  mapping (uint256 => address) internal tokenLeasor;

  mapping (address => uint256) internal leasedTokensCount;

  uint256 highestId = 1;

  constructor (string memory _name, string memory _symbol) public ERC721(_name, _symbol) {
  }

  function getNewId() public view returns(uint256) {
    return highestId;
  }

  function leasorOf(uint256 _tokenId) public view returns (address) {
    address owner = tokenLeasor[_tokenId];
    require(owner != address(0));
    return owner;
  }

  function balanceOfLeasor(address _leasor) public view returns (uint256) {
    require(_leasor != address(0));
    return leasedTokensCount[_leasor];
  }

  function tokenOfLeasorByIndex(address _leasor,uint256 _index) public view returns (uint256){
    require(_index < balanceOfLeasor(_leasor));
    return leasedTokens[_leasor][_index];
  }

  function addTokenToLeasor(address _to, uint256 _tokenId) internal {
    require(tokenLeasor[_tokenId] == address(0));
    tokenLeasor[_tokenId] = _to;
    leasedTokensCount[_to] = leasedTokensCount[_to].add(1);
    uint256 length = leasedTokens[_to].length;
    leasedTokens[_to].push(_tokenId);
    leasedTokensIndex[_tokenId] = length;
  }

  function removeTokenFromLeasor(address _from, uint256 _tokenId) internal {
    require(leasorOf(_tokenId) == _from);
    leasedTokensCount[_from] = leasedTokensCount[_from].sub(1);
    tokenLeasor[_tokenId] = address(0);

    uint256 tokenIndex = leasedTokensIndex[_tokenId];
    uint256 lastTokenIndex = leasedTokens[_from].length.sub(1);
    uint256 lastToken = leasedTokens[_from][lastTokenIndex];

    leasedTokens[_from][tokenIndex] = lastToken;
    leasedTokens[_from][lastTokenIndex] = 0;
    leasedTokens[_from].pop();
    delete leasedTokensIndex[_tokenId];
    leasedTokensIndex[lastToken] = tokenIndex;
  }

  function setLeaseExchange(address _leaseExchange) public onlyOwner {
    leaseExchange = _leaseExchange;
  }

  function totalAmount() external view returns (uint256) {
    uint256 amount = 0;
    for(uint256 i = 0; i < totalSupply(); i++){
      amount += metadata[tokenByIndex(i)].amount;
    }
    return amount;
  }

  function setMetadata(uint256 _tokenId, uint256 amount, address leasor, uint256 expiry) internal {
    require(_exists(_tokenId));
    metadata[_tokenId]= Metadata(amount,leasor,expiry,false);
  }

  function getMetadata(uint256 _tokenId) public view returns (uint256, address, uint256, uint256,uint256, bool) {
    require(_exists(_tokenId));
    return (
      metadata[_tokenId].amount,
      metadata[_tokenId].leasor,
      metadata[_tokenId].expiry,
      metadata[_tokenId].isMining
    );
  }

  function getAmountForUser(address owner) external view returns (uint256) {
    uint256 amount = 0;
    uint256 numTokens = balanceOf(owner);

    for(uint256 i = 0; i < numTokens; i++){
      amount += metadata[tokenOfOwnerByIndex(owner,i)].amount;
    }
    return amount;
  }

  function getAmountForUserMining(address owner) external view returns (uint256) {
    uint256 amount = 0;
    uint256 numTokens = balanceOf(owner);

    for(uint256 i = 0; i < numTokens; i++){
      if(metadata[tokenOfOwnerByIndex(owner,i)].isMining) {
        amount += metadata[tokenOfOwnerByIndex(owner,i)].amount;
      }
    }
    return amount;
  }

  function getAmount(uint256 _tokenId) public view returns (uint256) {
    require(_exists(_tokenId));
    return metadata[_tokenId].amount;
  }

  function getExpiry(uint256 _tokenId) public view returns (uint256) {
    require(exists(_tokenId));
    return metadata[_tokenId].expiry;
  }

  function getIsMining(uint256 _tokenId) public view returns (bool) {
    require(_exists(_tokenId));
    return metadata[_tokenId].isMining;
  }

  function startMining(address _owner, uint256 _tokenId) public returns (bool) {
    require(msg.sender == leaseExchange);
    require(_exists(_tokenId));
    require(ownerOf(_tokenId) == _owner);
    require(block.timestamp < metadata[_tokenId].expiry);
    require(metadata[_tokenId].isMining == false);
    Metadata storage m = metadata[_tokenId];
    m.isMining = true;
    return true;
  }

  function canRetrieveEMB(address _leasor, uint256 _tokenId) public view returns (bool) {
    require(_exists(_tokenId));
    require(metadata[_tokenId].leasor == _leasor);
    return(block.timestamp > metadata[_tokenId].expiry);
  }

  function endLease(address _leasee, uint256 _tokenId) public {
    require(msg.sender == leaseExchange);
    require(_exists(_tokenId));
    require(ownerOf(_tokenId) == _leasee);
    require(block.timestamp > metadata[_tokenId].expiry);
    removeTokenFromLeasor(metadata[_tokenId].leasor, _tokenId);
    _burn(_tokenId);
  }

  function splitLEMB(uint256 _tokenId, uint256 amount) public {
    require(_exists(_tokenId));
    require(ownerOf(_tokenId) == msg.sender);
    require(metadata[_tokenId].isMining == false);
    require(block.timestamp < metadata[_tokenId].expiry);
    require(amount < getAmount(_tokenId));

    uint256 _newTokenId = getNewId();

    Metadata storage m = metadata[_tokenId];
    m.amount = m.amount - amount;

    _mint(msg.sender, _newTokenId);
    addTokenToLeasor(m.leasor, _newTokenId);
    setMetadata(_newTokenId, amount, m.leasor, m.expiry);
    highestId = highestId + 1;
  }

  function mintUniqueTokenTo(address _to, uint256 amount, address leasor, uint256 expiry) public {
    require(msg.sender == leaseExchange);
    uint256 _tokenId = getNewId();
    _mint(_to, _tokenId);
    addTokenToLeasor(leasor, _tokenId);
    //need to check expiry
    setMetadata(_tokenId, amount, leasor, expiry);
    highestId = highestId + 1;
  }

  function _burn(uint256 _tokenId) override internal {
    super._burn(_tokenId);
    delete metadata[_tokenId];
  }

  modifier canTransfer(uint256 _tokenId) {
    require(_isApprovedOrOwner(msg.sender, _tokenId));
    require(metadata[_tokenId].isMining == false);
    _;
  }

}
