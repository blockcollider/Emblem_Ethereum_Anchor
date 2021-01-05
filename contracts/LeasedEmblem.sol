pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721Token.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract LeasedEmblem is  ERC721Token, Ownable {


  address internal leaseExchange;


  struct Metadata {
    uint256 amount;
    address leasor;
    uint256 duration;
    uint256 tradeExpiry;
    uint256 leaseExpiry;
    bool isMining;
  }


  mapping(uint256 => Metadata) public metadata;


  mapping(address => uint256[]) internal leasedTokens;


  mapping(uint256 => uint256) internal leasedTokensIndex;


  mapping (uint256 => address) internal tokenLeasor;


  mapping (address => uint256) internal leasedTokensCount;

  uint256 highestId = 1;

  uint256 sixMonths       = 15768000;

  constructor (string _name, string _symbol) public ERC721Token(_name, _symbol) {
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
    leasedTokens[_from].length--;
    leasedTokensIndex[_tokenId] = 0;
    leasedTokensIndex[lastToken] = tokenIndex;
  }

  function setLeaseExchange(address _leaseExchange) public onlyOwner {
    leaseExchange = _leaseExchange;
  }

  function totalAmount() external view returns (uint256) {
    uint256 amount = 0;
    for(uint256 i = 0; i < allTokens.length; i++){
      amount += metadata[allTokens[i]].amount;
    }
    return amount;
  }

  function setMetadata(uint256 _tokenId, uint256 amount, address leasor, uint256 duration,uint256 tradeExpiry, uint256 leaseExpiry) internal {
    require(exists(_tokenId));
    metadata[_tokenId]= Metadata(amount,leasor,duration,tradeExpiry,leaseExpiry,false);
  }

  function getMetadata(uint256 _tokenId) public view returns (uint256, address, uint256, uint256,uint256, bool) {
    require(exists(_tokenId));
    return (
      metadata[_tokenId].amount,
      metadata[_tokenId].leasor,
      metadata[_tokenId].duration,
      metadata[_tokenId].tradeExpiry,
      metadata[_tokenId].leaseExpiry,
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
    require(exists(_tokenId));
    return metadata[_tokenId].amount;
  }

  function getTradeExpiry(uint256 _tokenId) public view returns (uint256) {
    require(exists(_tokenId));
    return metadata[_tokenId].tradeExpiry;
  }

  function getDuration(uint256 _tokenId) public view returns (uint256) {
    require(exists(_tokenId));
    return metadata[_tokenId].duration;
  }

  function getIsMining(uint256 _tokenId) public view returns (bool) {
    require(exists(_tokenId));
    return metadata[_tokenId].isMining;
  }

  function startMining(address _owner, uint256 _tokenId) public returns (bool) {
    require(msg.sender == leaseExchange);
    require(exists(_tokenId));
    require(ownerOf(_tokenId) == _owner);
    require(now < metadata[_tokenId].tradeExpiry);
    require(metadata[_tokenId].isMining == false);
    Metadata storage m = metadata[_tokenId];
    m.isMining = true;
    m.leaseExpiry = now + m.duration;
    return true;
  }

  function canRetrieveEMB(address _leasor, uint256 _tokenId) public view returns (bool) {
    require(exists(_tokenId));
    require(metadata[_tokenId].leasor == _leasor);
    if(metadata[_tokenId].isMining == false) {
      return(now > metadata[_tokenId].leaseExpiry);
    }
    else {
      return(now > metadata[_tokenId].tradeExpiry);
    }
  }

  function endLease(address _leasee, uint256 _tokenId) public {
    require(msg.sender == leaseExchange);
    require(exists(_tokenId));
    require(ownerOf(_tokenId) == _leasee);
    require(now > metadata[_tokenId].leaseExpiry);
    removeTokenFromLeasor(metadata[_tokenId].leasor, _tokenId);
    _burn(_leasee, _tokenId);
  }

  function splitLEMB(uint256 _tokenId, uint256 amount) public {
    require(exists(_tokenId));
    require(ownerOf(_tokenId) == msg.sender);
    require(metadata[_tokenId].isMining == false);
    require(now < metadata[_tokenId].tradeExpiry);
    require(amount < getAmount(_tokenId));

    uint256 _newTokenId = getNewId();

    Metadata storage m = metadata[_tokenId];
    m.amount = m.amount - amount;

    _mint(msg.sender, _newTokenId);
    addTokenToLeasor(m.leasor, _newTokenId);
    setMetadata(_newTokenId, amount, m.leasor, m.duration,m.tradeExpiry, 0);
    highestId = highestId + 1;
  }

  function mintUniqueTokenTo(address _to, uint256 amount, address leasor, uint256 duration) public {
    require(msg.sender == leaseExchange);
    uint256 _tokenId = getNewId();
    _mint(_to, _tokenId);
    addTokenToLeasor(leasor, _tokenId);
    uint256 tradeExpiry = now + sixMonths;
    setMetadata(_tokenId, amount, leasor, duration,tradeExpiry, 0);
    highestId = highestId + 1;
  }

  function _burn(address _owner, uint256 _tokenId) internal {
    super._burn(_owner, _tokenId);
    delete metadata[_tokenId];
  }

  modifier canTransfer(uint256 _tokenId) {
    require(isApprovedOrOwner(msg.sender, _tokenId));
    require(metadata[_tokenId].isMining == false);
    _;
  }

}
