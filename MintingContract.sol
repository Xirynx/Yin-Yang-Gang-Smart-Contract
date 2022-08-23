// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "erc721a/contracts/ERC721A.sol";
import "erc721a/contracts/extensions/ERC721ABurnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract YinYangGangNFT is ERC721A("Yin Yang Gang", "YYG"), ERC721ABurnable, Ownable {
    uint256 public maxSupply; //Maximum mintable supply
    uint256 public mintPrice; //Mint Price for RAFFLE and PUBLIC

    bytes32 public merkleRoot;
    
    enum Phase{ 
        NONE,
        RAFFLE,
        WHITELIST,
        PUBLIC
    } //Phases of the mint. Raffle will be 1 per wallet, whitelist is varying amounts per wallet, public is free for all, 1 per tx.

    Phase currentPhase = Phase.NONE; //Declare + Initialise phase enum. Maybe unecessary to provide intial value...?

    string internal yin; //Night traits
    string internal yang; //Day traits

    //Max supply can be set multiple times, but must always be higher than current supply and not 0.
    function setMaxSupply(uint256 value) public onlyOwner { 
        require(value > 0 && value <= 10000 && totalSupply() <= value,  "Invalid max supply");
        maxSupply = value;
    }
    
    //Mint price can be set manually if needed.
    function setMintPrice(uint256 _mintPrice) public onlyOwner { 
        mintPrice = _mintPrice;
    }

    //Merkle root can be set manually if needed
    function setMerkleRoot(bytes32 _merkleRoot) public onlyOwner { 
        merkleRoot = _merkleRoot;
    }

    //New merkle tree, supply, and mint price must be defined to switch to the next phase.
    function cyclePhases(bytes32 _newMerkleRoot, uint256 _newSupply, uint256 _newMintPrice) external onlyOwner { 
        setMintPrice(_newMintPrice);
        setMerkleRoot(_newMerkleRoot);
        setMaxSupply(_newSupply);
        currentPhase = Phase((uint8(currentPhase) + 1) % 4); //Cycle through enum elements (phases) in order.
    }

    //Immediately stops mint phases.
    function stopAllPhases() external onlyOwner { 
        currentPhase = Phase.NONE;
    }

    //Jump to a specific phase if necessary.
    function setSpecificPhase(Phase _phase) external onlyOwner { 
        currentPhase = _phase;
    }

    //Set night time base URI
    function setYin(string calldata _yin) external onlyOwner { 
        yin = _yin;
    }

    //Set day time base URI
    function setYang(string calldata _yang) external onlyOwner { 
        yang = _yang;
    }

    //Switch to night time base URI at 22h00 UTC. Switch back to day time at 08h00 UTC
    function _baseURI() internal view override returns (string memory) {
        if (((block.timestamp + 7200) % 86400) < 36000) {
            return yin; 
        } else {
            return yang;
        }
    }

    //Merkle tree verification for single mint phases such as raffle
    function verifySingleMint(address wallet, bytes32[] calldata _merkleProof) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(wallet));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);       
    }

    //Merkle tree verification for multi-mint phases such as whitelist. Each wallet may have a different amount of allowed mints.
    function verifyMultiMint(bytes memory data, bytes32[] calldata _merkleProof) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(data));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    //Raffle mint. 1 per wallet.
    function raffleMint(bytes32[] calldata _merkleProof) external payable {
        require(currentPhase == Phase.RAFFLE, "Whitelist sale not started"); 
        require(msg.value >= mintPrice, "Insufficient funds");
        require(verifySingleMint(msg.sender, _merkleProof), "Incorrect merkle tree proof");
        require(totalSupply() < maxSupply, "Max supply exceeded");
        uint64 auxData = _getAux(msg.sender);
        require(auxData & 1 == 0, "Max mint for this phase exceeded");
        _setAux(msg.sender, auxData | 1); //Setting bit 0 to keep track of raffle mint
        _mint(msg.sender, 1);
    }

    //Whitelist mint. Varying amount of mints per wallet. Decoded in merkle tree leaves. Format of merkle tree leaves: abi.encode(address wallet, uint256 mintAllowance)
    function whitelistMint(uint256 amount, bytes32[] calldata _merkleProof) external {
        require(currentPhase == Phase.WHITELIST, "Whitelist sale not started"); 
        bytes memory data = abi.encode(msg.sender, amount);
        require(verifyMultiMint(data, _merkleProof), "Incorrect merkle tree proof");
        require(totalSupply() + amount <= maxSupply, "Max supply exceeded");
        uint64 auxData = _getAux(msg.sender);
        require(auxData & (1 << 1) == 0, "Max mint for this phase exceeded");
        _setAux(msg.sender, auxData | (1 << 1)); //Setting bit 1 to keep track of whitelist mint
        _mint(msg.sender, amount);
    }

    //Public mint. Free for all, 1 mint per transaction, no contracts allowed.
    function publicMint() external payable {
        require(currentPhase == Phase.PUBLIC, "Public sale not started");
        require(tx.origin == msg.sender, "Caller is not origin");
        require(msg.value >= mintPrice, "Insufficient funds");
        require(totalSupply() < maxSupply, "Max supply exceeded");
        _mint(msg.sender, 1);
    }

    //Admin mint for airdrops/marketing
    function adminMint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= maxSupply, "Max supply exceeded");
        require(amount <= 30, "Mint amount too large for one transaction");
        _mint(to, amount);        
    }

    //Withdraw Eth in contract to specified address
    function withdrawFunds(address to) external onlyOwner {
        payable(to).transfer(address(this).balance);
    }
}