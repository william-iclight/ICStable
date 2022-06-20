/**
 * Module     : ICStable.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: Decentralized stablecoin protocols on the IC network.
 * Refers     : https://github.com/iclighthouse/
 */

import Array "mo:base/Array";
import Binary "lib/Binary";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import DRC20 "lib/DRC20";
import ICTokens "lib/ICTokens";
import DIP20 "lib/DIP20Types";
import DRC207 "lib/DRC207";
import Deque "mo:base/Deque";
import Float "mo:base/Float";
import Hex "lib/Hex";
import Int "mo:base/Int";
import Int64 "mo:base/Int64";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Hash "mo:base/Hash";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import SHA224 "lib/SHA224";
import Tools "lib/Tools";
import SagaTM "ICTC/SagaTM";
import Time "mo:base/Time";
import Trie "./lib/Trie";
import ICOracle "./lib/ICOracle";
import ICSwap "./lib/ICSwap";
import T "./lib/ICStable";
import Result "mo:base/Result";
import Error "mo:base/Error";

shared(installMsg) actor class ICStable() = this {
    type Config = T.Config;
    type ConfigRequest = T.ConfigRequest;
    type Permyriad = T.Permyriad; // ‱ permyriad
    type AccountId = T.AccountId;
    type Address = T.Address;
    type Timestamp = T.Timestamp; // seconds
    type Price = T.Price;
    type TokenId = T.TokenId;
    type TokenStd = T.TokenStd;
    type TokenInfo = T.TokenInfo;
    type Balance = T.Balance;
    type CollShares = T.CollShares;
    type CollInfo = T.CollInfo;
    type CollInfoRequest = T.CollInfoRequest;
    type Yield = T.Yield;
    type CallbackLog = T.CallbackLog;
    type AssetResponse = T.AssetResponse;
    type StatsResponse = T.StatsResponse;
    type Dpid = T.Dpid;
    type Txid = T.Txid;
    type Nonce = T.Nonce;
    type Sa = T.Sa;
    type Data = T.Data;
    type CollValues = T.CollValues;
    type Action = T.Action;
    type Status = T.Status;
    type OperationType = T.OperationType;
    type ClosingType = T.ClosingType;
    type ChargeMethod = T.ChargeMethod;
    type DebtPosition = T.DebtPosition;
    type BalanceChange = T.BalanceChange;
    type TxnRecord = T.TxnRecord;
    type DebtPositionLog = T.DebtPositionLog;
    type TxnResult = T.TxnResult;
    type TrieList<K, V> = T.TrieList<K, V>;

    private func _now() : Timestamp{ return Int.abs(Time.now() / 1000000000); };
    private func _natToFloat(_n: Nat) : Float{ return Float.fromInt64(Int64.fromNat64(Nat64.fromNat(_n))); };
    private func _floatToNat(_f: Float) : Nat{ return Int.abs(Float.toInt(_f)); };
    private func _natToBlob(_n: Nat) : Blob{ return Blob.fromArray(Binary.BigEndian.fromNat64(Nat64.fromNat(_n))); }; 
    private func _blobToNat(_b: Blob) : Nat{ return Nat64.toNat(Binary.BigEndian.toNat64(Blob.toArray(_b))); };
    private func keyp(t: Principal) : Trie.Key<Principal> { return { key = t; hash = Principal.hash(t) }; };
    private func keyn(t: Nat) : Trie.Key<Nat> { return { key = t; hash = Hash.hash(t) }; };
    private func keyb(t: Blob) : Trie.Key<Blob> { return { key = t; hash = Blob.hash(t) }; };
    // Variables
    private let name_: Text = "";
    private let version_: Text = "0.1";
    private stable var pause: Bool = false; 
    private stable var owner: Principal = installMsg.caller;
    private stable var setting: Config = {
        DUSD = Principal.fromText("2l63q-hyaaa-aaaak-aaosa-cai");
        ICL = Principal.fromText("2x2bb-qyaaa-aaaak-aaoqa-cai");
        ICORACLE = Principal.fromText("6insc-piaaa-aaaak-aaoja-cai");
        ORACLE_INTERVAL = 30; // seconds
        LIQUIDATION_INTERVAL = 30; // seconds
        ASSESSING_INTERVAL = 8 * 3600; // 8h
        DEBT_CEILING = 100000000000; //DUSD per borrower
        DEBT_FLOOR = 100000000; //DUSD per borrower
        INIT_COLL_RATIO = 20000; // ‱ permyriad = Collateral*factor / DebtDUSD * 10000
        MIN_COLL_RATIO = 13500; // ‱ permyriad = (Collateral*factor-STABILITY_FEE) / DebtDUSD * 10000
        INIT_STABILITY_FEE = 500; // ‱ permyriad APY
        LIQUIDATION_FEE = 1000; // ‱ permyriad = Penalty / Collateral * 10000
    };
    private stable var tokenInfo: Trie.Trie<TokenId, TokenInfo> = Trie.empty();
    private stable var collInfo: Trie.Trie<TokenId, CollInfo> = Trie.empty();
    //private stable var collShares: Trie.Trie<TokenId, (balance: Nat, shares: CollShares)> = Trie.empty();
    private stable var stabilityFee = List.nil<(Nat, Timestamp)>(); // ‱ permyriad (Variable Annual Fee)
    private stable var oracleData = List.nil<(Timestamp, [ICOracle.DataResponse])>();
    //private stable var principalMap: Trie.Trie<AccountId, (Principal, Timestamp)> = Trie.empty();
    private stable var nonces: Trie.Trie<AccountId, Nonce> = Trie.empty(); 
    private stable var lastCallbacks = List.nil<CallbackLog>();
    private stable var iclBurned: Nat = 0;
    private stable var adjustFactorTime: Timestamp = 0; 
    private stable var factorCollCeiling: Nat = 10000;
    private stable var factorColls: Trie.Trie<TokenId, {collFactor: Nat; lpDiscountRate: Nat}> = Trie.empty();
    // pool
    private stable var supply: Nat = 0; // DUSD
    private stable var reserve: Int = 0; // DUSD
    private stable var assets: Trie.Trie<TokenId, (balance: Nat, shares: CollShares)> = Trie.empty(); // Collateral
    private stable var liquidities: Trie.Trie<TokenId, Nat> = Trie.empty(); // DUSD+Collateral
    private stable var liquidityYields: Trie.Trie<TokenId, List.List<Yield>> = Trie.empty();
    private stable var liquidityMiningRate = List.nil<(Nat, Timestamp)>(); // mint ICL 
    // borrower
    //private stable var debtTotal: Nat = 0;  // DUSD == supply
    //private stable var collTotal: Trie.Trie<TokenId, CollShares> = Trie.empty(); // Collateral == assets
    private stable var debtIndex: Nat = 1;
    private stable var borrowers: Trie.Trie<AccountId, (debt: Nat, dpids: [Dpid])> = Trie.empty();
    private stable var debts: Trie.Trie<Dpid, DebtPosition> = Trie.empty();
    private stable var logs: Trie.Trie<Dpid, DebtPositionLog> = Trie.empty();
    // LP
    private stable var lpTotal: Balance = {
        balance = 0; // DUSD
        rewards = List.nil<(TokenId, Nat)>(); // Collateral + Mining(ICL)
        timestamp = _now();  // Time of update (The latest time node in Yield)
    };
    private stable var lpBalances: Trie.Trie<AccountId, Balance> = Trie.empty();

    // ICTC functions
    private var saga: ?SagaTM.SagaTM = null;
    private func _getSaga() : SagaTM.SagaTM {
        switch(saga){
            case(?(_saga)){ return _saga };
            case(_){
                let _saga = SagaTM.SagaTM(Principal.fromActor(this), _local, null, null); //_taskCallback _orderCallback
                saga := ?_saga;
                return _saga;
            };
        };
    };
    private func _buildTask(_dpid: ?Dpid, _callee: Principal, _callType: SagaTM.CallType, _preTtid: [SagaTM.Ttid]) : SagaTM.PushTaskRequest{
        var gasCycles = 0;
        if (_isToken(_callee)){
            gasCycles := _tokenInfo(_callee).gasCycles;
        };
        var data: ?Blob = null;
        if (Option.isSome(_dpid)){
            data := ?_natToBlob(Option.get(_dpid, 0));
        };
        return {
            callee = _callee;
            callType = _callType;
            preTtid = _preTtid;
            attemptsMax = ?1;
            recallInterval = ?0; // nanoseconds
            cycles = gasCycles;
            data = data;
        };
    };
    private func _local(_args: SagaTM.CallType, _receipt: ?SagaTM.Receipt) : async (SagaTM.TaskResult){
        switch(_args){
            case(#This(method)){
                switch(method){
                    case(#dp_compOpen(_dpid)){
                        _dp_compOpen(_dpid);
                        return (#Done, ?#This(#dp_compOpen), null);
                    };
                    case(#dp_open(_dpid)){
                        _dp_open(_dpid);
                        return (#Done, ?#This(#dp_open), null);
                    };
                    case(#dp_compAdd(_dpid)){
                        _dp_compAdd(_dpid);
                        return (#Done, ?#This(#dp_compAdd), null);
                    };
                    case(#dp_add(_dpid, _addColls)){
                        _dp_add(_dpid, _addColls);
                        return (#Done, ?#This(#dp_add), null);
                    };
                    case(#dp_remove(_dpid, _toid, _txn)){
                        _dp_remove(_dpid, _toid, _txn);
                        return (#Done, ?#This(#dp_remove), null);
                    };
                    case(#dp_generate(_dpid, _toid, _txn)){
                        _dp_generate(_dpid, _toid, _txn);
                        return (#Done, ?#This(#dp_generate), null);
                    };
                    case(#dp_compClose(_dpid)){
                        _dp_compClose(_dpid);
                        return (#Done, ?#This(#dp_compClose), null);
                    };
                    case(#dp_close(_dpid, _toid, _txn, _closingType, _sfee, _penalty)){
                        _dp_close(_dpid, _toid, _txn, _closingType, _sfee, _penalty);
                        return (#Done, ?#This(#dp_close), null);
                    };
                    //case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; }); };
                };
            };
            case(_){ return (#Error, null, ?{code=#future(9901); message="Non-local function."; });};
        };
    };
    // Task callback
    // private func _taskCallback(_ttid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult) : async (){
    // };
    // Order callback
    // private func _orderCallback(_toid: SagaTM.Toid, _status: SagaTM.OrderStatus, _data: ?Blob) : async (){
    //     assert(Option.isSome(_data));
    //     let dpid = _blobToNat(Option.get(_data, Blob.fromArray([])));
    //     switch(Trie.get(debts, keyn(dpid), Nat.equal)){
    //         case(?(dp)){
    //             //
    //         };
    //         case(_){};
    //     };
    // };
    // cancel DP
    private func _dp_compOpen(_dpid: Dpid) : (){
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = 0; // *
                    collaterals = []; // *
                    doing = null; // *
                    status = #Cancelled; // *
                    payable = 0;
                    timestamp = _now(); // *
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                _clearLog();
            };
            case(_){};
        };
    };
    // open DP
    private func _dp_open(_dpid: Dpid) : (){
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                var transactions : [(SagaTM.Toid, Action, TxnRecord)] = [];
                switch(dp.doing){
                    case(?(toid, action, txn)){transactions := [(toid, action, txn)]; };
                    case(_){};
                };
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = dp.debt; // *
                    collaterals = dp.collaterals; // *
                    doing = null; // *
                    status = #Opening; // *
                    payable = 0;
                    timestamp = _now(); // *
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                for (coll in dp_.collaterals.vals()){
                    _addAssetBalance(coll.0, coll.1, coll.2);
                };
                supply += dp_.debt;
                _addBorrowerDP(dp_.borrower, dp_.debt, _dpid);
                let log: DebtPositionLog = {
                    borrower = dp_.borrower;
                    debtPeak = dp_.debt;
                    status = dp_.status;
                    transactions = transactions;
                    closingType = null;
                    stabilityCosts = 0; // ICL
                    liquidationPenalty = []; // Collateral
                    openingTime = dp.timestamp; 
                    updatedTime = dp_.timestamp;
                };
                logs := Trie.put(logs, keyn(_dpid), Nat.equal, log).0;
                _clearLog();
            };
            case(_){ assert(false); };
        };
    };
    // comp_add DP
    private func _dp_compAdd(_dpid: Dpid) : (){
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                var doing: ?(Nat, Action, TxnRecord) = dp.doing;
                switch(doing){
                    case(?(d)){ if (d.1 == #Adding){ doing := null } };
                    case(_){};
                };
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = dp.debt; 
                    collaterals = dp.collaterals; 
                    doing = doing; //*
                    status = dp.status; 
                    payable = dp.payable;
                    timestamp = dp.timestamp; 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                _clearLog();
            };
            case(_){};
        };
    };
    // add coll to DP
    private func _dp_add(_dpid: Dpid, _addColls: [(TokenId, Nat, CollShares)]){ //Backward
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                switch(dp.doing){
                    case(?(d)){ if (d.1 != #Adding){ assert(false); } };
                    case(_){};
                };
                var transactions : [(Nat, Action, TxnRecord)] = [];
                switch(dp.doing){
                    case(?(toid, action, txn)){transactions := [(toid, action, txn)]; };
                    case(_){};
                };
                var collaterals = dp.collaterals;
                for (addColl in _addColls.vals()){
                    collaterals := _addCollToDP(addColl, collaterals);
                    _addAssetBalance(addColl.0, addColl.1, addColl.2);
                };
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = dp.debt; 
                    collaterals = collaterals; // *
                    doing = null;  // *
                    status = dp.status; 
                    payable = dp.payable;
                    timestamp = dp.timestamp; 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                switch(Trie.get(logs, keyn(_dpid), Nat.equal)){
                    case(?(log)){
                        let log_: DebtPositionLog = {
                            borrower = log.borrower;
                            debtPeak = Nat.max(log.debtPeak, dp_.debt);
                            status = log.status;
                            transactions = Tools.arrayAppend(log.transactions, transactions); // *
                            closingType = log.closingType;
                            stabilityCosts = log.stabilityCosts; // ICL
                            liquidationPenalty = log.liquidationPenalty; // Collateral
                            openingTime = log.openingTime; 
                            updatedTime = _now();
                        };
                        logs := Trie.put(logs, keyn(_dpid), Nat.equal, log_).0;
                    };
                    case(_){};
                };
                _clearLog();
            };
            case(_){ assert(false); };
        };
    };
    // remove coll from DP
    private func _dp_remove(_dpid: Dpid, _toid: Nat, _txn: TxnRecord){ // Forward
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                var transactions : [(SagaTM.Toid, Action, TxnRecord)] = [(_toid, #Removing, _txn)];
                var doing: ?(Nat, Action, TxnRecord) = dp.doing;
                switch(doing){
                    case(?(d)){ if (d.1 == #Removing){ doing := null } };
                    case(_){};
                };
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = dp.debt; 
                    collaterals = dp.collaterals;
                    doing = doing;  // *
                    status = dp.status; 
                    payable = dp.payable;
                    timestamp = dp.timestamp; 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                switch(Trie.get(logs, keyn(_dpid), Nat.equal)){
                    case(?(log)){
                        let log_: DebtPositionLog = {
                            borrower = log.borrower;
                            debtPeak = Nat.max(log.debtPeak, dp_.debt);
                            status = log.status;
                            transactions = Tools.arrayAppend(log.transactions, transactions); // *
                            closingType = log.closingType;
                            stabilityCosts = log.stabilityCosts; // ICL
                            liquidationPenalty = log.liquidationPenalty; // Collateral
                            openingTime = log.openingTime; 
                            updatedTime = _now(); // *
                        };
                        logs := Trie.put(logs, keyn(_dpid), Nat.equal, log_).0;
                    };
                    case(_){};
                };
                _clearLog();
            };
            case(_){ assert(false); };
        };
    };
    // generate dusd from DP
    private func _dp_generate(_dpid: Dpid, _toid: Nat, _txn: TxnRecord){  // Forward
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                var transactions : [(SagaTM.Toid, Action, TxnRecord)] = [(_toid, #Borrowing, _txn)];
                var doing: ?(Nat, Action, TxnRecord) = dp.doing;
                switch(doing){
                    case(?(d)){ if (d.1 == #Borrowing){ doing := null } };
                    case(_){};
                };
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = dp.debt; 
                    collaterals = dp.collaterals;
                    doing = doing;  // *
                    status = dp.status; 
                    payable = dp.payable;
                    timestamp = dp.timestamp; 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                switch(Trie.get(logs, keyn(_dpid), Nat.equal)){
                    case(?(log)){
                        let log_: DebtPositionLog = {
                            borrower = log.borrower;
                            debtPeak = Nat.max(log.debtPeak, dp_.debt);
                            status = log.status;
                            transactions = Tools.arrayAppend(log.transactions, transactions); // *
                            closingType = log.closingType;
                            stabilityCosts = log.stabilityCosts; // ICL
                            liquidationPenalty = log.liquidationPenalty; // Collateral
                            openingTime = log.openingTime; 
                            updatedTime = _now(); // *
                        };
                        logs := Trie.put(logs, keyn(_dpid), Nat.equal, log_).0;
                    };
                    case(_){};
                };
                _clearLog();
            };
            case(_){ assert(false); };
        };
    };
    // comp_add DP
    private func _dp_compClose(_dpid: Dpid) : (){
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = dp.debt; 
                    collaterals = dp.collaterals; 
                    doing = null; //*
                    status = #Opening; 
                    payable = dp.payable;
                    timestamp = dp.timestamp; 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                _clearLog();
            };
            case(_){};
        };
    };
    // close DP
    private func _dp_close(_dpid: Dpid, _toid: Nat, _txn: TxnRecord, _closingType: ClosingType, _sfee: Nat, _penalty: [(TokenId, Nat)]){  // Forward
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){
                supply -= dp.debt;
                var ops = _txn.operations;
                let saga = _getSaga();
                // colls transfer; assert-;
                saga.open(_toid);
                for((tokenId_, iAmount_, cShares_) in dp.collaterals.vals()){
                    let token = _tokenInfo(tokenId_);
                    let coll = _collInfo(tokenId_);
                    let cAmount = _sharesToAmount(tokenId_, cShares_);
                    if (cAmount > token.gasToken*2){
                        ops := Tools.arrayAppend(ops, [(#Withdraw, tokenId_, ?#CreditRecord(cAmount))]);
                        var task3 = _buildTask(?_dpid, tokenId_, #DRC20(#transfer(_toAddress(dp.borrower), Nat.sub(cAmount, token.gasToken), null, null, ?_txn.txid)), []);
                        if (token.std == #dip20){
                            task3 := _buildTask(?_dpid, tokenId_, #DIP20(#transfer(Option.get(dp.principalId, Principal.fromActor(this)), Nat.sub(cAmount, token.gasToken))), []);
                        };
                        let ttid3 = saga.push(_toid, task3, null, null);
                    };
                    _removeAssetBalance(tokenId_, cAmount, cShares_); 
                };
                saga.finish(_toid);
                let txnNew: TxnRecord = {
                    txid = _txn.txid;
                    accountId = _txn.accountId;
                    index = _txn.index; // dpid
                    nonce = _txn.nonce;
                    operations = ops;
                    time = _txn.time;
                    data = _txn.data;
                };
                var transactions : [(SagaTM.Toid, Action, TxnRecord)] = [(_toid, #Closing, txnNew)];
                let dp_: DebtPosition = {
                    borrower = dp.borrower;
                    principalId = dp.principalId;
                    debt = 0; 
                    collaterals = [];
                    doing = null;  // *
                    status = #Closed; 
                    payable = 0;
                    timestamp = dp.timestamp; 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp_).0;
                switch(Trie.get(logs, keyn(_dpid), Nat.equal)){
                    case(?(log)){
                        let log_: DebtPositionLog = {
                            borrower = log.borrower;
                            debtPeak = Nat.max(log.debtPeak, dp_.debt);
                            status = #Closed;
                            transactions = Tools.arrayAppend(log.transactions, transactions); // *
                            closingType = ?_closingType;
                            stabilityCosts = _sfee; 
                            liquidationPenalty = _penalty; // Collateral
                            openingTime = log.openingTime; 
                            updatedTime = _now(); // *
                        };
                        logs := Trie.put(logs, keyn(_dpid), Nat.equal, log_).0;
                    };
                    case(_){};
                };
                _clearLog();
            };
            case(_){ assert(false); };
        };
    };

    // Local functions
    // trie list (Unsorted)
    private func trieItems<K, V>(_trie: Trie.Trie<K,V>, _page: Nat, _size: Nat) : TrieList<K, V> {
        let length = Trie.size(_trie);
        if (_page < 1 or _size < 1){
            return {data = []; totalPage = 0; total = length; };
        };
        let offset = Nat.sub(_page, 1) * _size;
        var totalPage: Nat = length / _size;
        if (totalPage * _size < length) { totalPage += 1; };
        if (offset >= length){
            return {data = []; totalPage = totalPage; total = length; };
        };
        let end: Nat = offset + Nat.sub(_size, 1);
        var i: Nat = 0;
        var res: [(K, V)] = [];
        for ((k,v) in Trie.iter<K, V>(_trie)){
            if (i >= offset and i <= end){
                res := Tools.arrayAppend(res, [(k,v)]);
            };
            i += 1;
        };
        return {data = res; totalPage = totalPage; total = length; };
    };
    private func _onlyOwner(_caller: Principal) : Bool { 
        return _caller == owner;
    };  // assert(_onlyOwner(msg.caller));
    private func _onlyDPOwner(_caller: AccountId, _dpid: Dpid) : Bool{
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(debt)){ return debt.borrower == _caller };
            case(_){ return false };
        };
    };
    private func _isToken(_tokenId: Principal) : Bool {
        return Option.isSome(Trie.get(tokenInfo, keyp(_tokenId), Principal.equal));
    };
    private func _isColl(_tokenId: Principal) : Bool {
        return Option.isSome(Trie.get(collInfo, keyp(_tokenId), Principal.equal));
    };
    private func _notPaused() : Bool { 
        return not(pause);
    };
    private func _getNonce(_a: AccountId): Nat{
        switch(Trie.get(nonces, keyb(_a), Blob.equal)){
            case(?(v)){
                return v;
            };
            case(_){
                return 0;
            };
        };
    };
    private func _addNonce(_a: AccountId): (){
        var n = _getNonce(_a);
        nonces := Trie.put(nonces, keyb(_a), Blob.equal, n+1).0;
        // index += 1;
    };
    private func _checkNonce(_a: AccountId, _nonce: ?Nonce) : Bool{
        switch(_nonce){
            case(?(n)){ return n == _getNonce(_a); };
            case(_){ return true; };
        };
    };
    private func _generateTxid(_app: Principal, _caller: AccountId, _nonce: Nat): Txid{
        let appType: [Nat8] = [76:Nat8, 69, 78, 68]; //LEND
        let canister: [Nat8] = Blob.toArray(Principal.toBlob(_app));
        let caller: [Nat8] = Blob.toArray(_caller);
        let nonce: [Nat8] = Binary.BigEndian.fromNat32(Nat32.fromNat(_nonce));
        let txInfo = Tools.arrayAppend(Tools.arrayAppend(Tools.arrayAppend(appType, canister), caller), nonce);
        let h224: [Nat8] = SHA224.sha224(txInfo);
        return Blob.fromArray(Tools.arrayAppend(nonce, h224));
    };
    // accountId
    private func _toAddress(_a: AccountId) : Address{
        return Hex.encode(Blob.toArray(_a));
    };
    private func _fromAdress(_address: Address): AccountId{
        switch (Tools.accountHexToAccountBlob(_address)){
            case(?(a)){
                return a;
            };
            case(_){
                var p = Principal.fromText(_address);
                var a = Tools.principalToAccountBlob(p, null);
                //_putPrincipal(a, p);
                return a;
            };
        };
    }; 
    private func _fromPrincipal(_p: Principal, _sa: ?[Nat8]): AccountId{
        let a = Tools.principalToAccountBlob(_p, _sa);
        //_putPrincipal(a, _p);
        return a;
    };
    // private func _toPrincipal(_a: AccountId) : Principal{
    //     switch(Trie.get(principalMap, keyb(_a), Blob.equal)){
    //         case(?(p)){ return p.0 };
    //         case(_) { assert(false); return Principal.fromActor(this); };
    //     };
    // };
    // private func _putPrincipal(_a: AccountId, _p: Principal) : (){
    //     principalMap := Trie.put(principalMap, keyb(_a), Blob.equal, (_p, _now())).0;
    //     principalMap := Trie.filter(principalMap, func (key:AccountId, value: (Principal,Timestamp)):Bool{ _inBorrowers(_a) or _inLPs(_a) or _now() < value.1 + 24 * 3600});
    // };
    // token
    private func _tokenInfo(_tokenId: TokenId) : TokenInfo{
        switch(Trie.get(tokenInfo, keyp(_tokenId), Principal.equal)){
            case(?(token)){ return token; };
            case(_){ assert(false); return {tokenId = Principal.fromText("2vxsx-fae"); symbol = ""; std = #other(""); decimals = 0; gasToken = 0; gasCycles = 0;} };
        };
    };
    private func _tokenStd(_tokenId: TokenId) : TokenStd{
        switch(Trie.get(tokenInfo, keyp(_tokenId), Principal.equal)){
            case(?(token)){ return token.std; };
            case(_){ return #other("Null") };
        };
    };
    private func _tokenDecimals(_tokenId: TokenId) : Nat{
        switch(Trie.get(tokenInfo, keyp(_tokenId), Principal.equal)){
            case(?(token)){ return Nat8.toNat(token.decimals); };
            case(_){ return 0; };
        };
    };
    private func _tokenDrc20(_tokenId: TokenId) : DRC20.Self{
        return actor(Principal.toText(_tokenId));
    };
    private func _tokenDip20(_tokenId: TokenId) : DIP20.Self{
        return actor(Principal.toText(_tokenId));
    };
    private func _syncToken(_tokenId: TokenId, _std: ?TokenStd) : async (){
        var std = Option.get(_std, #drc20);
        switch(Trie.get(tokenInfo, keyp(_tokenId), Principal.equal)){
            case(?(token)){ std := token.std; };
            case(_){};
        };
        if (std == #drc20){
            let drc20 = _tokenDrc20(_tokenId);
            var gasToken: Nat = 0;
            var gasCycles: Nat = 0;
            switch(await drc20.drc20_gas()){
                case(#token(v)){ gasToken := v; };
                case(#cycles(v)){ gasCycles := v; };
                case(_){};
            };
            tokenInfo := Trie.put<TokenId, TokenInfo>(tokenInfo, keyp(_tokenId), Principal.equal, {
                tokenId = _tokenId;
                symbol = await drc20.drc20_symbol();
                std = #drc20;
                decimals = await drc20.drc20_decimals();
                gasToken = gasToken;
                gasCycles = gasCycles;
            }).0;
            if (gasCycles > 0){ Cycles.add(gasCycles); };
            let msgTypes: [DRC20.MsgType] = [#onTransfer,#onLock,#onApprove]; //#onExecute,
            let res = await drc20.drc20_subscribe(tokenCallback, msgTypes, null);
        } else if (std == #dip20){
            let dip20 = _tokenDip20(_tokenId);
            tokenInfo := Trie.put<TokenId, TokenInfo>(tokenInfo, keyp(_tokenId), Principal.equal, {
                tokenId = _tokenId;
                symbol = await dip20.symbol();
                std = #dip20;
                decimals = await dip20.decimals();
                gasToken = await dip20.getTokenFee();
                gasCycles = 0;
            }).0;
        };
    };
    private func _syncTokens() : async (){
        for ((tokenId, info) in Trie.iter(tokenInfo)){
            await _syncToken(tokenId, null);
        };
    };
    private func _callback(_token: Principal, _txn: DRC20.TxnRecord) : async (){
        // action:  4bytes-operation[0:Nat8,0,0,1] + args
    };
    // Collateral
    private func _totalCollAmount(_tokenId: TokenId) : Nat{
        switch(Trie.get(assets, keyp(_tokenId), Principal.equal)){
            case(?(debt)){ return debt.0; };
            case(_){ return 0; };
        };
    };
    private func _collInfo(_tokenId: TokenId) : CollInfo{
        switch(Trie.get(collInfo, keyp(_tokenId), Principal.equal)){
            case(?(coll)){ return coll; };
            case(_){ 
                assert(false); 
                return {
                    swapPair = (Principal.fromText("2vxsx-fae"), #token0);
                    mktSid = 0;
                    dexSid = 0;
                    factor = 0;
                    totalCeiling = 0; 
                    lpDiscountRate = 0; 
                };
            };
        };
    };
    private func _collCeiling(_tokenId: TokenId) : Nat{ // **
        switch(Trie.get(collInfo, keyp(_tokenId), Principal.equal)){
            case(?(coll)){ 
                let factor: Nat = factorCollCeiling;
                return coll.totalCeiling * factor / 10000; 
            };
            case(_){ 
                return 0;
            };
        };
    };
    private func _initCollRatio() : Nat{ 
        return setting.INIT_COLL_RATIO; 
    };
    private func _minCollRatio() : Nat{
        return setting.MIN_COLL_RATIO; 
    };
    private func _stabilityFee() : (Nat, Timestamp){ // *
        switch(List.pop(stabilityFee).0){
            case(?(fee, ts)){ return (fee, ts); };
            case(_){ return (0,0); };
        };
    };
    private func _liquidationFee() : Nat{
        return setting.LIQUIDATION_FEE; 
    };
    private func _lpDiscountRate(_tokenId: TokenId) : Nat{ // **
        switch(Trie.get(collInfo, keyp(_tokenId), Principal.equal)){
            case(?(coll)){ 
                var factor: Nat = 10000;
                switch(Trie.get(factorColls, keyp(_tokenId), Principal.equal)){
                    case(?(factors)){ factor := factors.lpDiscountRate };
                    case(_){};
                };
                return coll.lpDiscountRate * factor / 10000; 
            };
            case(_){ 
                return 0;
            };
        };
    };
    private func _collFactor(_tokenId: TokenId) : Nat{ // **
        switch(Trie.get(collInfo, keyp(_tokenId), Principal.equal)){
            case(?(coll)){ 
                var factor: Nat = 10000;
                switch(Trie.get(factorColls, keyp(_tokenId), Principal.equal)){
                    case(?(factors)){ factor := factors.collFactor };
                    case(_){};
                };
                return coll.factor * factor / 10000; 
            };
            case(_){ 
                return 0;
            };
        };
    };
    // oracle
    private func _syncOracle() : async (){
        var latest: Timestamp = 0;
        let temp = List.pop(oracleData);
        switch(temp.0){
            case(?(ts, quotes)){ latest := ts; };
            case(_){};
        };
        if (_now() > latest + setting.ORACLE_INTERVAL){
            let oracle: ICOracle.Self = actor(Principal.toText(setting.ICORACLE));
            try{
                let data = await oracle.latest();
                oracleData := List.push((_now(), data), oracleData);
            } catch(e){};
        };
    };
    private func _price(_sid: Nat) : Price{
        switch(List.pop(oracleData).0){
            case(?(ts, data)){
                let temp = Array.find(data, func(t:ICOracle.DataResponse):Bool{ t.sid == _sid });
                switch(temp){
                    case(?(item)){
                        return (item.data.0, item.data.1, item.decimals);
                    };
                    case(_){ return (0,0,0); };
                };
            };
            case(_){ return (0,0,0); };
        };
    };
    // borrower
    private func _inBorrowers(_a: AccountId): Bool{
        return Option.isSome(Trie.get(borrowers, keyb(_a), Blob.equal));
    };
    private func _usdValue(_colls: [(_tokenId: TokenId, _amount: Nat)]) : Nat{ //usd (10**8)
        var res: Nat = 0;
        for ((_tokenId, _amount) in _colls.vals()){
            let token = _tokenInfo(_tokenId);
            let coll = _collInfo(_tokenId);
            let usd = _tokenInfo(setting.DUSD);
            let price = _price(coll.mktSid); // (ts, value, decimals)
            assert(price.1 > 0);
            res += _amount * price.1 * (10**Nat8.toNat(usd.decimals)) / (10**Nat8.toNat(token.decimals)) / (10**price.2);
        };
        return res;
    };
    private func _usdValueAdjusted(_colls: [(_tokenId: TokenId, _amount: Nat)]) : Nat{ //usd (10**8)
        var res: Nat = 0;
        for ((_tokenId, _amount) in _colls.vals()){
            let token = _tokenInfo(_tokenId);
            let coll = _collInfo(_tokenId);
            let usd = _tokenInfo(setting.DUSD);
            let price = _price(coll.mktSid); // (ts, value, decimals)
            assert(price.1 > 0);
            res += _amount * price.1 * (10**Nat8.toNat(usd.decimals)) * _collFactor(_tokenId) / 10000 / (10**Nat8.toNat(token.decimals)) / (10**price.2);
        };
        return res;
    };
    private func _getValueAdjusted(_colls: [CollValues]) : Nat{
        return _usdValueAdjusted(Array.map<CollValues, (TokenId,Nat)>(_colls, func (t:CollValues):(TokenId,Nat){ (t.0, _sharesToAmount(t.0, t.2)) }));
    };
    private func _generateUsd(_colls: [(_tokenId: TokenId, _amount: Nat)]) : Nat{
        return _usdValueAdjusted(_colls) * 10000 / _initCollRatio();
    };
    private func _debtToValue(_debt: Nat, _tokenId: TokenId) : Nat{ //USD (10**8)
        let coll = _collInfo(_tokenId);
        return _debt * _initCollRatio() / _collFactor(_tokenId); //  / 10000 * 10000
    };
    private func _debtToValueAdjusted(_debt: Nat, _tokenId: TokenId) : Nat{ //USD (10**8)
        let coll = _collInfo(_tokenId);
        return _debt * _initCollRatio() / 10000;//  / _collFactor(_tokenId) * 10000
    };
    private func _valueToCollAmount(_v: Nat, _tokenId: TokenId) : Nat{
        let token = _tokenInfo(_tokenId);
        let coll = _collInfo(_tokenId);
        let usd = _tokenInfo(setting.DUSD);
        let price = _price(coll.mktSid); // (ts, value, decimals)
        assert(price.1 > 0);
        return _v * (10**price.2) * (10**Nat8.toNat(token.decimals)) / (10**Nat8.toNat(usd.decimals)) / price.1;
    };
    private func _valueAdjustedToCollAmount(_va: Nat, _tokenId: TokenId) : Nat{
        let token = _tokenInfo(_tokenId);
        let coll = _collInfo(_tokenId);
        let usd = _tokenInfo(setting.DUSD);
        let price = _price(coll.mktSid); // (ts, value, decimals)
        assert(price.1 > 0);
        return _va * 10000 / _collFactor(_tokenId) * (10**price.2) * (10**Nat8.toNat(token.decimals)) / (10**Nat8.toNat(usd.decimals)) / price.1;
    };
    private func _valueToICL(_v: Nat) : Nat{
        let icl = _tokenInfo(setting.ICL);
        let usd = _tokenInfo(setting.DUSD);
        let price = _price(5); // icl.dexSid (ts, value, decimals)
        assert(price.1 > 0);
        return _v * (10**price.2) * (10**Nat8.toNat(icl.decimals)) / (10**Nat8.toNat(usd.decimals)) / price.1;
    };
    private func _collRatio(_colls: [CollValues], _debt: Nat, _payable: Nat) : Nat{ // permyriad
        return _getValueAdjusted(_colls) * 10000 / (_debt+_payable);
    };
    private func _amountToShares(_tokenId: TokenId, _amount: Nat) : Nat{
        switch(Trie.get(assets, keyp(_tokenId), Principal.equal)){
            case(?(balance, shares)){ 
                if (balance > 0 and shares > 0){
                    return _amount * shares / balance; 
                }else{
                    return _amount;
                };
            };
            case(_){ return _amount; }
        };
    };
    private func _sharesToAmount(_tokenId: TokenId, _shares: Nat) : Nat{
        switch(Trie.get(assets, keyp(_tokenId), Principal.equal)){
            case(?(balance, shares)){ 
                if (balance > 0 and shares > 0){
                    return _shares * balance / shares; 
                }else{
                    return _shares;
                };
            };
            case(_){ return _shares; }
        };
    };
    private func _addAssetBalance(_tokenId: TokenId, _amount: Nat, _shares: CollShares) : (){
        switch(Trie.get(assets, keyp(_tokenId), Principal.equal)){
            case(?(amount, shares)){
                assets := Trie.put(assets, keyp(_tokenId), Principal.equal, (amount + _amount, shares + _shares) ).0;
            };
            case(_){
                assets := Trie.put(assets, keyp(_tokenId), Principal.equal, (_amount, _shares) ).0;
            };
        };
    };
    private func _removeAssetBalance(_tokenId: TokenId, _amount: Nat, _shares: CollShares) : (){
        switch(Trie.get(assets, keyp(_tokenId), Principal.equal)){
            case(?(amount, shares)){ // TODO Nat.sub err.
                assets := Trie.put(assets, keyp(_tokenId), Principal.equal, (Nat.sub(Nat.max(amount,_amount), _amount), Nat.sub(Nat.max(shares,_shares), _shares)) ).0;
            };
            case(_){ assert(false); }; 
        };
    };
    private func _addBorrowerDP(_a: AccountId, _debt: Nat, _dpid: Dpid) : (){
        switch(Trie.get(borrowers, keyb(_a), Blob.equal)){
            case(?(totalDebt, dpids)){
                let dpids_ = Tools.arrayAppend(dpids, [_dpid]);
                borrowers := Trie.put(borrowers, keyb(_a), Blob.equal, (totalDebt + _debt, dpids_) ).0;
            };
            case(_){
                borrowers := Trie.put(borrowers, keyb(_a), Blob.equal, (_debt, [_dpid]) ).0;
            };
        };
    };
    private func _removeBorrowerDP(_a: AccountId, _dpid: Dpid) : (){
        switch(Trie.get(borrowers, keyb(_a), Blob.equal)){
            case(?(totalDebt, dpids)){
                let dpids_ = Array.filter(dpids, func (t:Dpid):Bool{ t != _dpid });
                borrowers := Trie.put(borrowers, keyb(_a), Blob.equal, (totalDebt, dpids_) ).0;
            };
            case(_){};
        };
    };
    private func _dpResponse(_dp: DebtPosition) : DebtPosition{
        let collaterals = Array.map(_dp.collaterals, func (t:CollValues):CollValues{
            (t.0, _sharesToAmount(t.0, t.2), t.2)
        });
        return {
            borrower = _dp.borrower;
            principalId = null;
            debt = _dp.debt; // DUSD
            collaterals = collaterals;
            doing = _dp.doing; // SagaTM.Toid
            status = _dp.status;
            payable = _calcStabilityFee(_dp.debt, _dp.timestamp) + _dp.payable;
            timestamp = _now(); // updated
        };
    };
    private func _inDP(_tokenId: TokenId, _colls: [CollValues]) : Bool{
        return Option.isSome(Array.find(_colls, func(t:CollValues):Bool{ t.0 == _tokenId }));
    };
    private func _getCollAmount(_tokenId: TokenId, _colls: [CollValues]) : (Nat, CollShares){
        switch(Array.find(_colls, func (t:CollValues):Bool{ t.0 == _tokenId })){
            case(?(item)){ return (_sharesToAmount(_tokenId, item.2), item.2) };
            case(_){ return (0, 0) };
        };
    };
    private func _addCollToDP(_add: CollValues, _colls: [CollValues]) : [CollValues]{
        var res = _colls;
        switch(Array.find(_colls, func(t:CollValues):Bool{ t.0 == _add.0 })){
            case(?(coll)){
                res := Array.filter(res, func(t:CollValues):Bool{ t.0 != _add.0 });
                res := Tools.arrayAppend(res, [(coll.0, coll.1 + _add.1, coll.2 + _add.2)]);
            };
            case(_){
                res := Tools.arrayAppend(res, [(_add.0, _add.1, _add.2)]);
            };
        };
        return res;
    };
    private func _removeCollFromDP(_remove: CollValues, _colls: [CollValues]) : [CollValues]{
        var res = _colls;
        switch(Array.find(_colls, func(t:CollValues):Bool{ t.0 == _remove.0 })){
            case(?(coll)){
                // if (_remove.2 > coll.2){ assert(false); };
                res := Array.filter(res, func(t:CollValues):Bool{ t.0 != _remove.0 });
                if (coll.2 > _remove.2){
                    res := Tools.arrayAppend(res, [(coll.0, Nat.sub(Nat.max(coll.1, _remove.1), _remove.1), Nat.sub(coll.2, _remove.2))]);
                };
            };
            case(_){ assert(false); };
        };
        return res;
    };
    private func _calcStabilityFee(_value: Nat, _from: Timestamp) : Nat{
        let now = _now();
        var list = stabilityFee;
        var isCompleted: Bool = false;
        var payable: Nat = 0;
        var updateTime: Timestamp = now;
        while (not(isCompleted)){
            let item = List.pop(list);
            let rate = item.0;
            list := item.1;
            switch(rate){
                case(?(r, ts)){
                    if (_from < ts){
                        payable += _value * (updateTime - ts) * r / 10000 / (365*24*3600);
                        updateTime := ts;
                    }else{
                        payable += _value * (updateTime - _from) * r / 10000 / (365*24*3600);
                        isCompleted := true;
                    };
                };
                case(_){ isCompleted := true; };
            };
        };
        return payable;
    };
    private func _reachCollCeiling(_colls: [CollValues]) : Bool{
        return Option.isSome(Array.find(_colls, func (t:CollValues):Bool{ _totalCollAmount(t.0) >= _collCeiling(t.0); }));
    };
    private func _burnICL() : async (){
        let icl = _tokenInfo(setting.ICL);
        let iclt: DRC20.Self = actor(Principal.toText(setting.ICL));
        let icle: ICTokens.Self = actor(Principal.toText(setting.ICL));
        let sub = Tools.getSubAccount(Principal.fromActor(this), 1);
        let contractSub = _fromPrincipal(Principal.fromActor(this), ?sub);
        let value = await iclt.drc20_balanceOf(_toAddress(contractSub));
        if (value > icl.gasToken * 10){
            let res = await icle.ictokens_burn(Nat.sub(value, icl.gasToken * 9), null, ?sub, null);
            iclBurned += Nat.sub(value, icl.gasToken * 9);
        };
    };
    private func _burn(_ttid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult): async (){
        let f = _burnICL();
        // if (_result.0 == #Done){ // burn icl
        //     switch(_task.callType){
        //         case(#DRC20(#transferFrom(from_, to_, iclFee_, nonce_, sa_, data_))){
        //             let f = _burnICL();
        //         };
        //         case(_){};
        //     };
        // };
    };
    // private func _burn2(_txid: Txid) : async (){
    //     let icl = _tokenInfo(setting.ICL);
    //     let iclColl = _collInfo(setting.ICL);
    //     let swapActor : ICSwap.Self = actor(Principal.toText(iclColl.swapPair.0));
    //     var iclValue: Nat = 0;
    //     switch(await swapActor.txnRecord(_txid)){
    //         case(?(txn)){
    //             switch(txn.token0Value){
    //                 case(#CreditRecord(v)){ if (iclColl.swapPair.1 == #token0){iclValue := v;} };
    //                 case(_){};
    //             };
    //             switch(txn.token1Value){
    //                 case(#CreditRecord(v)){ if (iclColl.swapPair.1 == #token1){iclValue := v;} };
    //                 case(_){};
    //             };
    //         };
    //         case(_){};
    //     };
    //     if (iclValue > icl.gasToken*2){
    //         let f = _burnICL(Nat.sub(iclValue, icl.gasToken));
    //         iclBurned += Nat.sub(iclValue, icl.gasToken);
    //     };
    // };
    private func _burnAfterSwap(_ttid: SagaTM.Ttid, _task: SagaTM.Task, _result: SagaTM.TaskResult): async (){
        let sub = Tools.getSubAccount(Principal.fromActor(this), 1);
        let contractSub = _fromPrincipal(Principal.fromActor(this), ?sub);
        let usd = _tokenInfo(setting.DUSD);
        let icl = _tokenInfo(setting.ICL);
        let iclColl = _collInfo(setting.ICL);
        let usdActor : DRC20.Self = actor(Principal.toText(setting.DUSD));
        let balance = await usdActor.drc20_balanceOf(_toAddress(contractSub));
        if (balance > usd.gasToken * 3){
            let saga = _getSaga();
            let toid = saga.create(#Backward, null, null);
            var task1 = _buildTask(null, setting.DUSD, #DRC20(#approve(Principal.toText(iclColl.swapPair.0), balance, null, ?sub, null)), []);
            var comp1 = _buildTask(null, setting.DUSD, #__skip, []);
            let ttid1 = saga.push(toid, task1, ?comp1, null);
            var task2 = _buildTask(null, iclColl.swapPair.0, #ICSwap(#swap2(setting.DUSD, Nat.sub(balance, usd.gasToken*2), null, ?sub, null)), []);
            let ttid2 = saga.push(toid, task2, null, null);
            saga.finish(toid); 
            let f = saga.run(toid);
        };
        let f = _burnICL();
    };
    private func _clearLog() : (){
        //debts
        //logs
        //borrowers
    };
    // LP
    private func _inLPs(_a: AccountId): Bool{
        return Option.isSome(Trie.get(lpBalances, keyb(_a), Blob.equal));
    };

    /// init
    public shared func init() : async Bool{
        await _syncToken(setting.DUSD, ?#drc20);
        await _syncToken(setting.ICL, ?#drc20);
        stabilityFee := List.push((setting.INIT_STABILITY_FEE, _now()), stabilityFee);
        return true;
    };
    public shared func syncToken(_tokenId: ?TokenId, _std: ?TokenStd) : async Bool{
        switch(_tokenId){
            case(?(tokenId)){ await _syncToken(tokenId, _std); };
            case(_){await _syncTokens();};
        };
        return true;
    };
    public shared func syncOracle() : async Bool{
        await _syncOracle();
        return true;
    };
    // drc20 token callback
    public shared(msg) func tokenCallback(txn: DRC20.TxnRecord) : async (){
        assert(_isToken(msg.caller));
        let f = _callback(msg.caller, txn);
    };
    public shared(msg) func tokenNotify(_token: Principal, _txid: Blob) : async (){
        assert(_onlyOwner(msg.caller));
        assert(_isToken(_token));
        let token: DRC20.Self = actor(Principal.toText(_token));
        let txn_ = await token.drc20_txnRecord(_txid);
        switch(txn_){
            case(?(txn)){ let f = _callback(_token, txn); };
            case(_){ assert(false); };
        };
    };

    // public functions
    public query func name() : async Text{
        return name_;
    };
    public query func version() : async Text{
        return version_;
    };
    //open '(vec{record{principal "2q3hv-5aaaa-aaaak-aaoqq-cai"; 100000000}}, null,null,null)'
    public shared(msg) func open(_coll: [(TokenId, Nat)], _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TxnResult{
        assert(_notPaused());
        let accountPrincipal = msg.caller;
        let account = _fromPrincipal(msg.caller, _sa);
        let tokenId = _coll[0].0;
        let contract = _fromPrincipal(Principal.fromActor(this), null);
        // check
        if (not(_checkNonce(account, _nonce))){ 
            return #err({code=#NonceError; message="Nonce error! The nonce should be "#Nat.toText(_getNonce(account))}); 
        };
        let token = _tokenInfo(tokenId);
        // if (token.std == #dip20){ assert(_sa == null); };
        let usd = _tokenInfo(setting.DUSD);
        let coll = _collInfo(tokenId);
        let nonce = _getNonce(account);
        let dpid = debtIndex;
        let txid = _generateTxid(Principal.fromActor(this), account, nonce);
        let price = _price(coll.mktSid); // (ts, value, decimals)
        if (price.1 == 0 or _now() > price.0 + 72 * 3600){
            let f = _syncOracle();
            return #err({code=#UnavailableOracle; message="Unavailable oracle.";});
        };
        let cAmount = _coll[0].1;
        let cShares = _amountToShares(tokenId, cAmount);
        let uAmount = _generateUsd([(tokenId, cAmount)]);
        if (uAmount > setting.DEBT_CEILING or uAmount < setting.DEBT_FLOOR){
            return #err({code=#InvalidAmount; message="Invalid amount. "}); 
        };
        if (cAmount < token.gasToken*2){
            return #err({code=#InvalidAmount; message="Invalid amount. "}); 
        };
        if (_totalCollAmount(tokenId) + cAmount > _collCeiling(tokenId)){
            return #err({code=#ReachedCollateralCeiling; message="The amount of collateral has reached its ceiling.";});
        };
        // ICTC: (1)transferFrom; (2)mint
        let saga = _getSaga();
        let toid = saga.create(#Backward, ?_natToBlob(dpid), null);
        // prepare
        var ops: [(OperationType, TokenId, ?BalanceChange)] = [];
        ops := Tools.arrayAppend(ops, [(#Deposit, tokenId, ?#DebitRecord(cAmount))]);
        ops := Tools.arrayAppend(ops, [(#Mint, setting.DUSD, ?#CreditRecord(uAmount))]);
        let txn: TxnRecord = {
            txid = txid;
            accountId = account;
            index = dpid; // dpid
            nonce = nonce;
            operations = ops;
            time = _now();
            data = _data;
        };
        let dp: DebtPosition = {
            borrower = account;
            principalId = ?accountPrincipal;
            debt = uAmount; // *
            collaterals = [(tokenId, cAmount, cShares)]; // *
            doing = ?(toid, #Opening, txn); // *
            status = #Prepared; // *
            payable = 0;
            timestamp = _now(); // *
        };
        debts := Trie.put(debts, keyn(dpid), Nat.equal, dp).0;
        var task0 = _buildTask(?dpid, Principal.fromActor(this), #__skip, []);
        var comp0 = _buildTask(?dpid, Principal.fromActor(this), #This(#dp_compOpen(dpid)), []);
        let ttid0 = saga.push(toid, task0, ?comp0, null);
        // #drc20: collateral
        var task1 = _buildTask(?dpid, tokenId, #DRC20(#transferFrom(_toAddress(account), _toAddress(contract), cAmount, null, null, ?txid)), []);
        var comp1 = _buildTask(?dpid, tokenId, #DRC20(#transfer(_toAddress(account), Nat.sub(cAmount, token.gasToken), null, null, ?txid)), []);
        // #dip20: collateral
        if (token.std == #dip20){ 
            task1 := _buildTask(?dpid, tokenId, #DIP20(#transferFrom(accountPrincipal, Principal.fromActor(this), cAmount)), []);
            comp1 := _buildTask(?dpid, tokenId, #DIP20(#transfer(accountPrincipal, Nat.sub(cAmount, token.gasToken))), []);
        };
        let ttid1 = saga.push(toid, task1, ?comp1, null);
        // #ictokens: dusd
        var task2 = _buildTask(?dpid, setting.DUSD, #ICTokens(#mint(_toAddress(account), uAmount, null, ?txid)), []);
        let ttid2 = saga.push(toid, task2, null, null); // blocking
        var task3 = _buildTask(?dpid, Principal.fromActor(this), #This(#dp_open(dpid)), []);
        let ttid3 = saga.push(toid, task3, null, null);
        saga.finish(toid); // Close task pushing
        let f = saga.run(toid);
        _addNonce(account);
        debtIndex += 1;
        return #ok({ dpid=dpid; txid=txid; });
    };
    //add '(6, vec{record{principal "2q3hv-5aaaa-aaaak-aaoqq-cai"; 100000000}}, null,null,null)'
    public shared(msg) func add(_dpid: Dpid, _coll: [(TokenId, Nat)], _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TxnResult{
        assert(_notPaused());
        let accountPrincipal = msg.caller;
        let account = _fromPrincipal(msg.caller, _sa);
        assert(_onlyDPOwner(account, _dpid));
        let tokenId = _coll[0].0;
        let contract = _fromPrincipal(Principal.fromActor(this), null);
        if (not(_checkNonce(account, _nonce))){ 
            return #err({code=#NonceError; message="Nonce error! The nonce should be "#Nat.toText(_getNonce(account))}); 
        };
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(debt)){
                assert(_inDP(tokenId, debt.collaterals));
                assert(debt.status == #Opening);
                if (Option.isSome(debt.doing)){
                    return #err({code=#UndefinedError; message="Previous transaction not completed.";});
                };
                let token = _tokenInfo(tokenId);
                let coll = _collInfo(tokenId);
                let nonce = _getNonce(account);
                let txid = _generateTxid(Principal.fromActor(this), account, nonce);
                let cAmount = _coll[0].1;
                let cShares = _amountToShares(tokenId, cAmount);
                if (cAmount < token.gasToken*2){
                    return #err({code=#InvalidAmount; message="Invalid amount. "}); 
                };
                // Stability Fee (payable+)
                var payable: Nat = _calcStabilityFee(debt.debt, debt.timestamp);
                if (_collRatio(_addCollToDP((tokenId, cAmount, cShares), debt.collaterals), debt.debt, payable) > _initCollRatio() 
                and _totalCollAmount(tokenId)+cAmount > _collCeiling(tokenId)){
                    return #err({code=#UndefinedError; message="A collateral for the debt has exceeded the ceiling.";});
                };
                var addColls: [(TokenId, Nat, CollShares)] = [(tokenId, cAmount, cShares)];
                var ops: [(OperationType, TokenId, ?BalanceChange)] = [];
                // ICTC
                let saga = _getSaga();
                let toid = saga.create(#Backward, ?_natToBlob(_dpid), null);
                ops := Tools.arrayAppend(ops, [(#Deposit, tokenId, ?#DebitRecord(cAmount))]);
                let txn: TxnRecord = {
                    txid = txid;
                    accountId = account;
                    index = _dpid; // dpid
                    nonce = nonce;
                    operations = ops;
                    time = _now();
                    data = _data;
                };
                let dp: DebtPosition = {
                    borrower = debt.borrower;
                    principalId = debt.principalId;
                    debt = debt.debt; 
                    collaterals = debt.collaterals; //_addCollToDP((tokenId, cAmount, cShares), debt.collaterals); 
                    doing = ?(toid, #Adding, txn); // *
                    status = debt.status; 
                    payable = debt.payable + payable; // DUSD
                    timestamp = _now(); 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp).0;
                var task0 = _buildTask(?_dpid, Principal.fromActor(this), #__skip, []);
                var comp0 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_compAdd(_dpid)), []);
                let ttid0 = saga.push(toid, task0, ?comp0, null);
                // #drc20: collateral
                var task1 = _buildTask(?_dpid, tokenId, #DRC20(#transferFrom(_toAddress(account), _toAddress(contract), cAmount, null, null, ?txid)), []);
                var comp1 = _buildTask(?_dpid, tokenId, #DRC20(#transfer(_toAddress(account), Nat.sub(cAmount, token.gasToken), null, null, ?txid)), []);
                // #dip20: collateral
                if (token.std == #dip20){ 
                    task1 := _buildTask(?_dpid, tokenId, #DIP20(#transferFrom(accountPrincipal, Principal.fromActor(this), cAmount)), []);
                    comp1 := _buildTask(?_dpid, tokenId, #DIP20(#transfer(accountPrincipal, Nat.sub(cAmount, token.gasToken))), []);
                };
                let ttid1 = saga.push(toid, task1, ?comp1, null);
                var task2 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_add(_dpid, addColls)), []);
                let ttid2 = saga.push(toid, task2, null, null);
                saga.finish(toid); // Close task pushing
                let f = saga.run(toid);
                _addNonce(account);
                return #ok({ dpid=_dpid; txid=txid; });
            };
            case(_){
                return #err({code=#UndefinedError; message="No debt position exist."}); 
            };
        };
    };
    //remove '(6, record{principal "2q3hv-5aaaa-aaaak-aaoqq-cai"; null}, null,null,null)'
    public shared(msg) func remove(_dpid: Dpid, _coll: (TokenId, ?CollShares), _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TxnResult{
        assert(_notPaused());
        let accountPrincipal = msg.caller;
        let account = _fromPrincipal(msg.caller, _sa);
        assert(_onlyDPOwner(account, _dpid));
        let tokenId = _coll.0;
        let contract = _fromPrincipal(Principal.fromActor(this), null);
        // check
        if (not(_checkNonce(account, _nonce))){ 
            return #err({code=#NonceError; message="Nonce error! The nonce should be "#Nat.toText(_getNonce(account))}); 
        };
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(debt)){
                assert(_inDP(tokenId, debt.collaterals));
                assert(debt.status == #Opening);
                if (Option.isSome(debt.doing)){
                    return #err({code=#UndefinedError; message="Previous transaction not completed.";});
                };
                let token = _tokenInfo(tokenId);
                let usd = _tokenInfo(setting.DUSD);
                let coll = _collInfo(tokenId);
                let nonce = _getNonce(account);
                let txid = _generateTxid(Principal.fromActor(this), account, nonce);
                let price = _price(coll.mktSid); // (ts, value, decimals)
                if (price.1 == 0 or _now() > price.0 + 72 * 3600){
                    let f = _syncOracle();
                    return #err({code=#UnavailableOracle; message="Unavailable oracle.";});
                };
                // Stability Fee (payable+)
                var payable: Nat = _calcStabilityFee(debt.debt, debt.timestamp);
                let cTotalValueAdjusted = _getValueAdjusted(debt.collaterals);
                let collShares = _getCollAmount(tokenId, debt.collaterals).1; // (Nat, CollShares)
                var cSharesAvailable:Nat = 0;
                let debtValue = debt.debt + debt.payable + payable;
                if (cTotalValueAdjusted > _debtToValueAdjusted(debtValue, tokenId)){
                    let valueAdjusted = Nat.sub(cTotalValueAdjusted, _debtToValueAdjusted(debtValue, tokenId)); 
                    cSharesAvailable := _amountToShares(tokenId, _valueAdjustedToCollAmount(valueAdjusted, tokenId));
                    cSharesAvailable := Nat.min(cSharesAvailable, collShares);
                };
                let cShares = Option.get(_coll.1, cSharesAvailable);
                let cAmount = _sharesToAmount(tokenId, cShares);
                let cValueAdjusted = _usdValueAdjusted([(tokenId, cAmount)]);
                if (cShares > cSharesAvailable or cAmount < token.gasToken*2){
                    return #err({code=#InvalidAmount; message="Invalid amount. "}); 
                };
                if (Nat.sub(cTotalValueAdjusted, cValueAdjusted) * 10000 / debtValue < _initCollRatio()){
                    return #err({code=#InvalidAmount; message="Invalid amount. Withdrawal of up to "#Nat.toText(cSharesAvailable)#" shares."}); 
                };
                // ICTC: 
                let saga = _getSaga();
                let toid = saga.create(#Forward, ?_natToBlob(_dpid), null);
                // prepare
                var ops: [(OperationType, TokenId, ?BalanceChange)] = [];
                ops := Tools.arrayAppend(ops, [(#Withdraw, tokenId, ?#CreditRecord(cAmount))]);
                let txn: TxnRecord = {
                    txid = txid;
                    accountId = account;
                    index = _dpid; // dpid
                    nonce = nonce;
                    operations = ops;
                    time = _now();
                    data = _data;
                };
                let dp: DebtPosition = {
                    borrower = debt.borrower;
                    principalId = debt.principalId;
                    debt = debt.debt; 
                    collaterals = _removeCollFromDP((tokenId, cAmount, cShares), debt.collaterals); 
                    doing = ?(toid, #Removing, txn); // *
                    status = debt.status; // *
                    payable = debt.payable + payable;
                    timestamp = _now(); 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp).0;
                _removeAssetBalance(tokenId, cAmount, cShares);
                // #drc20: collateral
                var task1 = _buildTask(?_dpid, tokenId, #DRC20(#transfer(_toAddress(account), Nat.sub(cAmount, token.gasToken), null, null, ?txid)), []);
                // #dip20: collateral
                if (token.std == #dip20){ 
                    task1 := _buildTask(?_dpid, tokenId, #DIP20(#transfer(accountPrincipal, Nat.sub(cAmount, token.gasToken))), []);
                };
                let ttid1 = saga.push(toid, task1, null, null);
                var task2 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_remove(_dpid, toid, txn)), []);
                let ttid2 = saga.push(toid, task2, null, null);
                saga.finish(toid); // Close task pushing
                let f = saga.run(toid);
                _addNonce(account);
                return #ok({ dpid=_dpid; txid=txid; });
            };
            case(_){
                return #err({code=#UndefinedError; message="No debt position exist."}); 
            };
        };
    };
    //generate '(6, opt 100000000, null,null,null)'
    public shared(msg) func generate(_dpid: Dpid, _amount: ?Nat, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TxnResult{
        assert(_notPaused());
        let accountPrincipal = msg.caller;
        let account = _fromPrincipal(msg.caller, _sa);
        assert(_onlyDPOwner(account, _dpid));
        let contract = _fromPrincipal(Principal.fromActor(this), null);
        // check
        if (not(_checkNonce(account, _nonce))){ 
            return #err({code=#NonceError; message="Nonce error! The nonce should be "#Nat.toText(_getNonce(account))}); 
        };
        let usd = _tokenInfo(setting.DUSD);
        let nonce = _getNonce(account);
        let txid = _generateTxid(Principal.fromActor(this), account, nonce);
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(debt)){
                assert(debt.status == #Opening);
                if (_reachCollCeiling(debt.collaterals)){
                    return #err({code=#UndefinedError; message="A collateral for the debt has exceeded the ceiling.";});
                };
                if (Option.isSome(debt.doing)){
                    return #err({code=#UndefinedError; message="Previous transaction not completed.";});
                };
                // Stability Fee (payable+)
                var payable: Nat = _calcStabilityFee(debt.debt, debt.timestamp);
                let uAmountTest = _generateUsd(Array.map<CollValues, (TokenId,Nat)>(debt.collaterals, func (t:CollValues):(TokenId,Nat){
                    (t.0, _sharesToAmount(t.0, t.2))
                }));
                if (uAmountTest <= debt.debt){
                    return #err({code=#UndefinedError; message="Insufficient collateral.";});
                };
                let uAmountAvailable = Nat.min(Nat.sub(uAmountTest, debt.debt + debt.payable + payable), setting.DEBT_CEILING);
                let uAmount = Option.get(_amount, uAmountAvailable);
                if (uAmount > uAmountAvailable){
                    return #err({code=#InvalidAmount; message="Invalid amount."}); 
                };
                // ICTC: 
                let saga = _getSaga();
                let toid = saga.create(#Forward, ?_natToBlob(_dpid), null);
                // prepare
                var ops: [(OperationType, TokenId, ?BalanceChange)] = [];
                ops := Tools.arrayAppend(ops, [(#Mint, setting.DUSD, ?#CreditRecord(uAmount))]);
                let txn: TxnRecord = {
                    txid = txid;
                    accountId = account;
                    index = _dpid; // dpid
                    nonce = nonce;
                    operations = ops;
                    time = _now();
                    data = _data;
                };
                let dp: DebtPosition = {
                    borrower = debt.borrower;
                    principalId = debt.principalId;
                    debt = debt.debt + uAmount; 
                    collaterals = debt.collaterals; 
                    doing = ?(toid, #Borrowing, txn); // *
                    status = debt.status;
                    payable = debt.payable + payable;
                    timestamp = _now(); 
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp).0;
                supply += uAmount;
                var task1 = _buildTask(?_dpid, setting.DUSD, #ICTokens(#mint(_toAddress(account), uAmount, null, ?txid)), []);
                let ttid1 = saga.push(toid, task1, null, null);
                var task2 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_generate(_dpid, toid, txn)), []);
                let ttid2 = saga.push(toid, task2, null, null);
                saga.finish(toid); // Close task pushing
                let f = saga.run(toid);
                _addNonce(account);
                return #ok({ dpid=_dpid; txid=txid; });
            };
            case(_){
                return #err({code=#UndefinedError; message="No debt position exist."}); 
            };
        };
    };
    //payback '(12, variant{DUSD}, null,null,null)'
    public shared(msg) func payback(_dpid: Dpid, _chargeMethod: ChargeMethod, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TxnResult{
        assert(_notPaused());
        let accountPrincipal = msg.caller;
        let account = _fromPrincipal(msg.caller, _sa);
        assert(_onlyDPOwner(account, _dpid));
        let contract = _fromPrincipal(Principal.fromActor(this), null);
        let sub = Tools.getSubAccount(Principal.fromActor(this), 1);
        let contractSub = _fromPrincipal(Principal.fromActor(this), ?sub);
        // check
        if (not(_checkNonce(account, _nonce))){ 
            return #err({code=#NonceError; message="Nonce error! The nonce should be "#Nat.toText(_getNonce(account))}); 
        };
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(debt)){
                assert(debt.status == #Opening);
                let usd = _tokenInfo(setting.DUSD);
                let icl = _tokenInfo(setting.ICL);
                let iclColl = _collInfo(setting.ICL);
                let nonce = _getNonce(account);
                let txid = _generateTxid(Principal.fromActor(this), account, nonce);
                // Stability Fee (payable+)
                var payable: Nat = _calcStabilityFee(debt.debt, debt.timestamp) + debt.payable;
                var uAmount = debt.debt;
                var transferFromValue = uAmount;
                var iclFee: Nat = 0;
                if (_chargeMethod == #ICL){
                    iclFee := _valueToICL(payable)  // -> ICL 
                }else{
                    transferFromValue += payable;
                };
                var ops: [(OperationType, TokenId, ?BalanceChange)] = [];
                // ICTC
                let saga = _getSaga();
                let toid = saga.create(#Backward, ?_natToBlob(_dpid), null);
                var task0 = _buildTask(?_dpid, Principal.fromActor(this), #__skip, []);
                var comp0 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_compClose(_dpid)), []);
                let ttid0 = saga.push(toid, task0, ?comp0, null);
                ops := Tools.arrayAppend(ops, [(#Deposit, setting.DUSD, ?#DebitRecord(transferFromValue))]);
                var task1 = _buildTask(?_dpid, setting.DUSD, #DRC20(#transferFrom(_toAddress(account), _toAddress(contract), transferFromValue, null, null, ?txid)), []);
                var comp1 = _buildTask(?_dpid, setting.DUSD, #DRC20(#transfer(_toAddress(account), Nat.sub(transferFromValue, usd.gasToken), null, null, ?txid)), []);
                let ttid1 = saga.push(toid, task1, ?comp1, null);
                // Stability Fee (Start: Forward)
                if (_chargeMethod == #ICL and iclFee > icl.gasToken){
                    ops := Tools.arrayAppend(ops, [(#Deposit, setting.ICL, ?#DebitRecord(iclFee))]);
                    var task2 = _buildTask(?_dpid, setting.ICL, #DRC20(#transferFrom(_toAddress(account), _toAddress(contractSub), iclFee, null, null, ?txid)), []);
                    let ttid2 = saga.push(toid, task2, null, ?_burn);
                } else if (_chargeMethod == #DUSD and payable > usd.gasToken*2){
                    ops := Tools.arrayAppend(ops, [(#Burn, setting.DUSD, ?#CreditRecord(payable))]);
                    var task2 = _buildTask(?_dpid, setting.DUSD, #DRC20(#transfer(_toAddress(contractSub), Nat.sub(payable, usd.gasToken), null, null, ?txid)), []);
                    let ttid2 = saga.push(toid, task2, null, ?_burnAfterSwap);
                };
                // burn DUSD; supply-;
                ops := Tools.arrayAppend(ops, [(#Burn, setting.DUSD, ?#DebitRecord(debt.debt))]);
                var task4 = _buildTask(?_dpid, setting.DUSD, #ICTokens(#burn(uAmount, null, null, ?txid)), []);
                let ttid4 = saga.push(toid, task4, null, null);
                // local payback ( save DP; save log)
                let txn: TxnRecord = {
                    txid = txid;
                    accountId = account;
                    index = _dpid; // dpid
                    nonce = nonce;
                    operations = ops;
                    time = _now();
                    data = _data;
                };
                var task5 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_close(_dpid, toid, txn, #Payback, payable, [])), []);
                let ttid5 = saga.push(toid, task5, null, null);
                saga.finish(toid); // Close task pushing
                let f = saga.run(toid);
                let dp: DebtPosition = {
                    borrower = debt.borrower;
                    principalId = debt.principalId;
                    debt = debt.debt; // *
                    collaterals = debt.collaterals; // *
                    doing = ?(toid, #Closing, txn); // *
                    status = #Closing; // *
                    payable = payable;
                    timestamp = _now();
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp).0;
                _addNonce(account);
                return #ok({ dpid=_dpid; txid=txid; });
            };
            case(_){
                return #err({code=#UndefinedError; message="No debt position exist."}); 
            };
        };
    };
    public shared(msg) func paybackTest(_dpid: Dpid, _chargeMethod: ChargeMethod, _nonce: ?Nonce, _sa: ?Sa, _data: ?Data) : async TxnResult{
        assert(_notPaused());
        let accountPrincipal = msg.caller;
        let account = _fromPrincipal(msg.caller, _sa);
        assert(_onlyDPOwner(account, _dpid));
        let contract = _fromPrincipal(Principal.fromActor(this), null);
        let sub = Tools.getSubAccount(Principal.fromActor(this), 1);
        let contractSub = _fromPrincipal(Principal.fromActor(this), ?sub);
        // check
        if (not(_checkNonce(account, _nonce))){ 
            return #err({code=#NonceError; message="Nonce error! The nonce should be "#Nat.toText(_getNonce(account))}); 
        };
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(debt)){
                assert(debt.status == #Opening);
                let usd = _tokenInfo(setting.DUSD);
                let icl = _tokenInfo(setting.ICL);
                let iclColl = _collInfo(setting.ICL);
                let nonce = _getNonce(account);
                let txid = _generateTxid(Principal.fromActor(this), account, nonce);
                // Stability Fee (payable+)
                var payable: Nat = _calcStabilityFee(debt.debt, debt.timestamp) + debt.payable;
                var uAmount = debt.debt;
                var transferFromValue = uAmount;
                var iclFee: Nat = 0;
                if (_chargeMethod == #ICL){
                    iclFee := _valueToICL(payable)  // -> ICL 
                }else{
                    transferFromValue += payable;
                };
                var ops: [(OperationType, TokenId, ?BalanceChange)] = [];
                // ICTC
                let saga = _getSaga();
                let toid = saga.create(#Backward, ?_natToBlob(_dpid), null);
                var task0 = _buildTask(?_dpid, Principal.fromActor(this), #__skip, []);
                var comp0 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_compClose(_dpid)), []);
                let ttid0 = saga.push(toid, task0, ?comp0, null);
                ops := Tools.arrayAppend(ops, [(#Deposit, setting.DUSD, ?#DebitRecord(transferFromValue))]);
                var task1 = _buildTask(?_dpid, setting.DUSD, #DRC20(#transferFrom(_toAddress(account), _toAddress(contract), transferFromValue, null, null, ?txid)), []);
                var comp1 = _buildTask(?_dpid, setting.DUSD, #DRC20(#transfer(_toAddress(account), Nat.sub(transferFromValue, usd.gasToken), null, null, ?txid)), []);
                let ttid1 = saga.push(toid, task1, ?comp1, null);
                // Stability Fee (Start: Forward)
                if (_chargeMethod == #ICL and iclFee > icl.gasToken){
                    ops := Tools.arrayAppend(ops, [(#Deposit, setting.ICL, ?#DebitRecord(iclFee))]);
                    var task2 = _buildTask(?_dpid, setting.ICL, #DRC20(#transferFrom(_toAddress(account), _toAddress(contractSub), iclFee, null, null, ?txid)), []);
                    let ttid2 = saga.push(toid, task2, null, ?_burn);
                } else if (_chargeMethod == #DUSD and payable > usd.gasToken*2){
                    ops := Tools.arrayAppend(ops, [(#Burn, setting.DUSD, ?#CreditRecord(payable))]);
                    var task2 = _buildTask(?_dpid, setting.DUSD, #DRC20(#transfer(_toAddress(contractSub), Nat.sub(payable, usd.gasToken), null, null, ?txid)), []);
                    let ttid2 = saga.push(toid, task2, null, ?_burnAfterSwap);
                };
                // burn DUSD; supply-;
                ops := Tools.arrayAppend(ops, [(#Burn, setting.DUSD, ?#DebitRecord(debt.debt))]);
                var task4_0 = _buildTask(?_dpid, Principal.fromActor(this), #__block, []);
                let ttid4_0 = saga.push(toid, task4_0, null, null);
                var task4 = _buildTask(?_dpid, setting.DUSD, #ICTokens(#burn(uAmount, null, null, ?txid)), []);
                let ttid4 = saga.push(toid, task4, null, null);
                // local payback ( save DP; save log)
                let txn: TxnRecord = {
                    txid = txid;
                    accountId = account;
                    index = _dpid; // dpid
                    nonce = nonce;
                    operations = ops;
                    time = _now();
                    data = _data;
                };
                var task5 = _buildTask(?_dpid, Principal.fromActor(this), #This(#dp_close(_dpid, toid, txn, #Payback, payable, [])), []);
                let ttid5 = saga.push(toid, task5, null, null);
                saga.finish(toid); // Close task pushing
                let f = saga.run(toid);
                let dp: DebtPosition = {
                    borrower = debt.borrower;
                    principalId = debt.principalId;
                    debt = debt.debt; // *
                    collaterals = debt.collaterals; // *
                    doing = ?(toid, #Closing, txn); // *
                    status = #Closing; // *
                    payable = payable;
                    timestamp = _now();
                };
                debts := Trie.put(debts, keyn(_dpid), Nat.equal, dp).0;
                _addNonce(account);
                return #ok({ dpid=_dpid; txid=txid; });
            };
            case(_){
                return #err({code=#UndefinedError; message="No debt position exist."}); 
            };
        };
    };

    // PCAFM & CRAFM
    private func _dusdRate() : Float{ //  <1:Devaluation  >1:Appreciation
        var dvalue: Nat = 0;
        var uvalue: Nat = 0;
        for ((tokenId, collInfo) in Trie.iter(collInfo)){
            if (collInfo.totalCeiling > 0){
                let dprice = _price(collInfo.dexSid);
                let uprice = _price(collInfo.mktSid);
                if (dprice.1 > 0 and uprice.1 > 0){
                    dvalue += collInfo.totalCeiling * dprice.1 / (10**dprice.2);
                    uvalue += collInfo.totalCeiling * uprice.1 / (10**uprice.2);
                };
            };
        };
        if (dvalue > 0){
            return _natToFloat(uvalue) / _natToFloat(dvalue);
        }else{
            return 1.0;
        };
    };
    private func _pcafm() : async (){
        //collCeiling(*rate^2)     stabilityFee(*(2-rate)^8)
        let rate = Float.min(_dusdRate(), 2.0);
        factorCollCeiling := _floatToNat((rate ** 2)*10000);
        let factorFee = _floatToNat(((2.0 - rate) ** 8)*10000);
        let feePermyriad = Nat.max(setting.INIT_STABILITY_FEE * factorFee / 10000, 100);
        let temp = List.pop(stabilityFee);
        switch(temp.0){
            case(?(feeRate, ts)){
                if (feeRate != feePermyriad){
                    stabilityFee := List.push((feePermyriad, _now()), stabilityFee);
                };
            };
            case(_){};
        };
    };
    private func _crafm() : async (){
        //collFactor(*(1-(min(0.20, (volatility)^2))  lpDiscountRate(*(1+(min(0.20, (volatility)^2))) 
        for ((tokenId, collInfo) in Trie.iter(collInfo)){
            let sid = collInfo.mktSid;
            let oracle: ICOracle.Self = actor(Principal.toText(setting.ICORACLE));
            try{
                let volatility = await oracle.volatility(sid, 3600*24);
                let collFactor = (Nat.sub(10000, Nat.min(2000, _floatToNat(volatility**2 * 10000))));
                let lpDiscountRate = (10000 + Nat.min(2000, _floatToNat(volatility**2 * 10000)));
                factorColls := Trie.put(factorColls, keyp(tokenId), Principal.equal, {collFactor=collFactor; lpDiscountRate=lpDiscountRate}).0;
            } catch(e){};
        };
    };
    public shared(msg) func feedback() : async (){
        let interval: Nat = 3600*8;
        if (_now() / interval > adjustFactorTime / interval or _onlyOwner(msg.caller)){
            await _pcafm();
            await _crafm();
            adjustFactorTime := _now();
        };
    };

    // query
    public shared func test() : async (Nat, Nat, Nat){
        let temp1 = Trie.filter(debts, func(k:Dpid, v:DebtPosition):Bool{ v.status == #Opening });
        let temp2 = Trie.filter(debts, func(k:Dpid, v:DebtPosition):Bool{ v.status != #Opening });
        let temp3 = Trie.filter(debts, func(k:Dpid, v:DebtPosition):Bool{ v.status == #Opening or v.status != #Opening });
        return (Trie.size(temp1), Trie.size(temp2), Trie.size(temp3));
    };
    public query func tokens() : async [(TokenId, TokenInfo)]{
        return Iter.toArray(Trie.iter(tokenInfo));
    };
    public query func collaterals() : async [(TokenId, CollInfo, CollInfo)]{
        return Array.map<(TokenId, CollInfo), (TokenId, CollInfo, CollInfo)>(Iter.toArray(Trie.iter(collInfo)), func (t:(TokenId, CollInfo)):(TokenId, CollInfo, CollInfo){
            return (t.0, t.1, {
                swapPair = t.1.swapPair;
                mktSid = t.1.mktSid;
                dexSid = t.1.dexSid;
                factor = _collFactor(t.0); // % permyriad
                totalCeiling = _collCeiling(t.0); // Collateral
                lpDiscountRate = _lpDiscountRate(t.0); // % permyriad  max:2000 min:0
            });
        });
    };
    public query func getPrice() : async ?(Timestamp, [ICOracle.DataResponse]){
        return List.pop(oracleData).0;
    };
    public query func stats() : async StatsResponse{
        var assetTotalValue: Nat = 0;
        var assetsArr: [(asset: AssetResponse, shares: Nat)] = [];
        var liquidity: Nat = 0;
        var openingDpCount: Nat = 0;
        for ((tokenId,(balance,shares)) in Trie.iter(assets)){
            let token = _tokenInfo(tokenId);
            let value = _usdValue([(tokenId, balance)]);
            assetsArr := Tools.arrayAppend(assetsArr, [({tokenId = tokenId; symbol = token.symbol; balance = balance; value = value}, shares)]);
            assetTotalValue += value;
        };
        switch(Trie.get(liquidities, keyp(setting.DUSD), Principal.equal)){
            case(?(v)){ liquidity := v; };
            case(_){};
        };
        let temp = Trie.filter(debts, func(k:Dpid, v:DebtPosition):Bool{ v.status == #Opening });
        openingDpCount := Trie.size(temp);
        // let temp = Array.filter(Iter.toArray(Trie.iter(debts)), func(t:(Dpid, DebtPosition)):Bool{ t.1.status == #Opening });
        // openingDpCount := temp.size(); 
        return {
            supply = supply; // DUSD
            assetTotalValue = assetTotalValue; // DUSD
            assets = assetsArr;
            reserve = reserve; // DUSD
            liquidity = liquidity;  // DUSD
            dpCount = Nat.sub(debtIndex, 1);
            openingDpCount = openingDpCount;
        };
    };
    public query func liquidity(_a: ?Address) : async (dusd: Nat, assets: [AssetResponse]){
        switch(_a){
            case(?(address)){
                let account = _fromAdress(address);
                // TODO
                return (0, []);
            };
            case(_){
                var dusd: Nat = 0;
                var assetsArr: [AssetResponse] = [];
                switch(Trie.get(liquidities, keyp(setting.DUSD), Principal.equal)){
                    case(?(v)){ dusd := v; };
                    case(_){};
                };
                for ((tokenId, balance) in Trie.iter(liquidities)){
                    if (tokenId != setting.DUSD){
                        let token = _tokenInfo(tokenId);
                        let value = _usdValue([(tokenId, balance)]);
                        assetsArr := Tools.arrayAppend(assetsArr, [{tokenId = tokenId; symbol = token.symbol; balance = balance; value = value}]);
                    };
                };
                return (dusd, assetsArr);
            };
        };
    };
    public query func dp(_dpid: Dpid) : async ?DebtPosition{
        switch(Trie.get(debts, keyn(_dpid), Nat.equal)){
            case(?(dp)){ return ?_dpResponse(dp); };
            case(_){ return null; };
        };
    };
    public query func dpList(_page: ?Nat, _size: ?Nat) : async TrieList<Dpid, DebtPosition>{
        let list = trieItems<Dpid, DebtPosition>(debts, Option.get(_page, 1), Option.get(_size, 50));
        return {data = Array.map<(Dpid,DebtPosition),(Dpid,DebtPosition)>(list.data, 
        func (t:(Dpid,DebtPosition)):(Dpid,DebtPosition){
            return (t.0, _dpResponse(t.1));
        }); total = list.total; totalPage = list.totalPage; };
    };
    public query func borrower(_a: Address) : async (debt: Nat, dps: [(Dpid, DebtPosition)], logs: [(Dpid, DebtPositionLog)]){ // first 100
        let account = _fromAdress(_a);
        switch(Trie.get(borrowers, keyb(account), Blob.equal)){
            case(?(item)){
                var dps: [(Dpid, DebtPosition)] = [];
                var dplogs: [(Dpid, DebtPositionLog)] = [];
                for(dpid in item.1.vals()){
                    switch(Trie.get(debts, keyn(dpid), Nat.equal)){
                        case(?(dp)){ dps := Tools.arrayAppend(dps, [(dpid, _dpResponse(dp))]); };
                        case(_){};
                    };
                    switch(Trie.get(logs, keyn(dpid), Nat.equal)){
                        case(?(log)){ dplogs := Tools.arrayAppend(dplogs, [(dpid, log)]); };
                        case(_){};
                    };
                };
                return (item.0, dps, dplogs);
            };
            case(_){ return (0, [], []) };
        };
    };
    public query func log(_dpid: Dpid) : async ?DebtPositionLog{
        return Trie.get(logs, keyn(_dpid), Nat.equal);
    };

    // manager
    public query func getConfig() : async (Config, Config){
        return (setting, {
            DUSD = setting.DUSD;
            ICL = setting.ICL;
            ICORACLE = setting.ICORACLE;
            ORACLE_INTERVAL = setting.ORACLE_INTERVAL;
            LIQUIDATION_INTERVAL = setting.LIQUIDATION_INTERVAL;
            ASSESSING_INTERVAL = setting.ASSESSING_INTERVAL;
            DEBT_CEILING = setting.DEBT_CEILING;
            DEBT_FLOOR = setting.DEBT_FLOOR;
            INIT_COLL_RATIO = _initCollRatio();
            MIN_COLL_RATIO = _minCollRatio();
            INIT_STABILITY_FEE = _stabilityFee().0;
            LIQUIDATION_FEE = _liquidationFee();
        });
    };
    public shared(msg) func config(config: ConfigRequest) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        setting := {
            DUSD = setting.DUSD;
            ICL = setting.ICL;
            ICORACLE = Option.get(config.ICORACLE, setting.ICORACLE);
            ORACLE_INTERVAL = Option.get(config.ORACLE_INTERVAL, setting.ORACLE_INTERVAL);
            LIQUIDATION_INTERVAL = Option.get(config.LIQUIDATION_INTERVAL, setting.LIQUIDATION_INTERVAL);
            ASSESSING_INTERVAL = Option.get(config.ASSESSING_INTERVAL, setting.ASSESSING_INTERVAL);
            DEBT_CEILING = Option.get(config.DEBT_CEILING, setting.DEBT_CEILING);
            DEBT_FLOOR = Option.get(config.DEBT_FLOOR, setting.DEBT_FLOOR);
            INIT_COLL_RATIO = Option.get(config.INIT_COLL_RATIO, setting.INIT_COLL_RATIO);
            MIN_COLL_RATIO = Option.get(config.MIN_COLL_RATIO, setting.MIN_COLL_RATIO);
            INIT_STABILITY_FEE = Option.get(config.INIT_STABILITY_FEE, setting.INIT_STABILITY_FEE);
            LIQUIDATION_FEE = Option.get(config.LIQUIDATION_FEE, setting.LIQUIDATION_FEE);
        };
        return true;
    };
    public query func getOwner() : async Principal{  
        return owner;
    };
    public shared(msg) func changeOwner(_newOwner: Principal) : async Bool{  
        assert(_onlyOwner(msg.caller));
        owner := _newOwner;
        return true;
    };
    public shared(msg) func setPause(_pause: Bool) : async Bool{ 
        assert(_onlyOwner(msg.caller));
        pause := _pause;
        return true;
    };
    //(principal "2q3hv-5aaaa-aaaak-aaoqq-cai", variant{drc20}, record{swapPair=record{principal "2m75e-kaaaa-aaaak-aaosq-cai";variant{token0}}; mktSid=2;dexSid=4;factor=8000;totalCeiling=100000000000;lpDiscountRate=1500})
    //(principal "2x2bb-qyaaa-aaaak-aaoqa-cai", variant{drc20}, record{swapPair=record{principal "2f4wy-4iaaa-aaaak-aaota-cai";variant{token0}}; mktSid=3;dexSid=5;factor=2000;totalCeiling=1000000000000;lpDiscountRate=1500})
    public shared(msg) func addCollateral(_tokenId: TokenId, _std: TokenStd, _coll: CollInfo) : async Bool{
        assert(_onlyOwner(msg.caller));
        assert(not(_isColl(_tokenId)));
        assert(_coll.factor <= 10000);
        assert(_coll.lpDiscountRate <= 2000);
        let f = _syncToken(_tokenId, ?_std);
        collInfo := Trie.put(collInfo, keyp(_tokenId), Principal.equal, _coll).0;
        return true;
    };
    public shared(msg) func updateCollateral(_coll: CollInfoRequest) : async Bool{
        assert(_onlyOwner(msg.caller));
        assert(_isColl(_coll.tokenId));
        assert(Option.get(_coll.factor, 0) <= 10000);
        assert(Option.get(_coll.lpDiscountRate, 0) <= 2000);
        await _syncToken(_coll.tokenId, null);
        switch(Trie.get(collInfo, keyp(_coll.tokenId), Principal.equal)){
            case(?(coll)){ 
                collInfo := Trie.put(collInfo, keyp(_coll.tokenId), Principal.equal, {
                    swapPair = Option.get(_coll.swapPair, coll.swapPair);
                    mktSid = Option.get(_coll.mktSid, coll.mktSid);
                    dexSid = Option.get(_coll.dexSid, coll.dexSid);
                    factor = Option.get(_coll.factor, coll.factor);
                    totalCeiling = Option.get(_coll.totalCeiling, coll.totalCeiling);
                    lpDiscountRate = Option.get(_coll.lpDiscountRate, coll.lpDiscountRate);
                }).0;
            };
            case(_){};
        };
        return true;
    };

    // ICTC: management functions
    private stable var ictc_admins: [Principal] = [];
    private func _onlyIctcAdmin(_caller: Principal) : Bool { 
        return Option.isSome(Array.find(ictc_admins, func (t: Principal): Bool{ t == _caller }));
    }; 
    private func _onlyBlocking(_toid: SagaTM.Toid) : Bool{
        switch(_getSaga().status(_toid)){
            case(?(status)){ return status == #Blocking };
            case(_){ return false; };
        };
    };
    public query func ictc_getAdmins() : async [Principal]{
        return ictc_admins;
    };
    public shared(msg) func ictc_addAdmin(_admin: Principal) : async (){
        assert(_onlyOwner(msg.caller));
        if (Option.isNull(Array.find(ictc_admins, func (t: Principal): Bool{ t == _admin }))){
            ictc_admins := Tools.arrayAppend(ictc_admins, [_admin]);
        };
    };
    public shared(msg) func ictc_removeAdmin(_admin: Principal) : async (){
        assert(_onlyOwner(msg.caller));
        ictc_admins := Array.filter(ictc_admins, func (t: Principal): Bool{ t != _admin });
    };
    public query func ictc_getTOCount() : async Nat{
        return _getSaga().count();
    };
    public query func ictc_getTO(_toid: SagaTM.Toid) : async ?SagaTM.Order{
        return _getSaga().getOrder(_toid);
    };
    public query func ictc_getTOs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Toid, SagaTM.Order)]; totalPage: Nat; total: Nat}{
        return _getSaga().getOrders(_page, _size);
    };
    public query func ictc_getTOPool() : async [(SagaTM.Toid, ?SagaTM.Order)]{
        return _getSaga().getAliveOrders();
    };
    public query func ictc_getTT(_ttid: SagaTM.Ttid) : async ?SagaTM.TaskEvent{
        return _getSaga().getActuator().getTaskEvent(_ttid);
    };
    public query func ictc_getTTByTO(_toid: SagaTM.Toid) : async [SagaTM.TaskEvent]{
        return _getSaga().getTaskEvents(_toid);
    };
    public query func ictc_getTTs(_page: Nat, _size: Nat) : async {data: [(SagaTM.Ttid, SagaTM.TaskEvent)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getTaskEvents(_page, _size);
    };
    public query func ictc_getTTPool() : async [(SagaTM.Ttid, SagaTM.Task)]{
        let pool = _getSaga().getActuator().getTaskPool();
        let arr = Array.map<(SagaTM.Ttid, SagaTM.Task), (SagaTM.Ttid, SagaTM.Task)>(pool, 
        func (item:(SagaTM.Ttid, SagaTM.Task)): (SagaTM.Ttid, SagaTM.Task){
            (item.0, item.1);
        });
        return arr;
    };
    public query func ictc_getTTErrors(_page: Nat, _size: Nat) : async {data: [(Nat, SagaTM.ErrorLog)]; totalPage: Nat; total: Nat}{
        return _getSaga().getActuator().getErrorLogs(_page, _size);
    };
    public query func ictc_getCalleeStatus(_callee: Principal) : async ?SagaTM.CalleeStatus{
        return _getSaga().getActuator().calleeStatus(_callee);
    };
    // Governance
    // public shared(msg) func ictc_clearTT() : async (){ // Warning: Execute this method with caution
    //     assert(_onlyOwner(msg.caller));
    //     _getSaga().getActuator().clearTasks();
    // };
    public shared(msg) func ictc_removeTT(_toid: SagaTM.Toid, _ttid: SagaTM.Ttid) : async ?SagaTM.Ttid{
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.open(_toid);
        let ttid = saga.remove(_toid, _ttid);
        saga.finish(_toid);
        return ttid;
    };
    public shared(msg) func ictc_appendTT(_dpid: Dpid, _toid: SagaTM.Toid, _callee: Principal, _callType: SagaTM.CallType, _preTtids: [SagaTM.Ttid]) : async SagaTM.Ttid{
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.open(_toid);
        let taskRequest = _buildTask(?_dpid, _callee, _callType, _preTtids);
        let ttid = saga.append(_toid, taskRequest, null, null);
        //saga.finish(_toid);
        //let f = saga.run(_toid);
        return ttid;
    };
    public shared(msg) func ictc_completeTO(_toid: SagaTM.Toid, _status: SagaTM.OrderStatus) : async Bool{
        assert(_onlyOwner(msg.caller) or _onlyIctcAdmin(msg.caller));
        assert(_onlyBlocking(_toid));
        let saga = _getSaga();
        saga.finish(_toid);
        let r = await saga.run(_toid);
        return await _getSaga().complete(_toid, _status);
    };

    // DRC207: ICMonitor
    /// DRC207 support
    public func drc207() : async DRC207.DRC207Support{
        return {
            monitorable_by_self = true;
            monitorable_by_blackhole = { allowed = true; canister_id = ?Principal.fromText("7hdtw-jqaaa-aaaak-aaccq-cai"); };
            cycles_receivable = true;
            timer = { enable = true; interval_seconds = null; }; 
        };
    };
    /// canister_status
    public func canister_status() : async DRC207.canister_status {
        let ic : DRC207.IC = actor("aaaaa-aa");
        await ic.canister_status({ canister_id = Principal.fromActor(this) });
    };
    /// receive cycles
    public func wallet_receive(): async (){
        let amout = Cycles.available();
        let accepted = Cycles.accept(amout);
    };
    /// timer tick
    public func timer_tick(): async (){
        let f = _syncOracle();
    };

    // upgrade
    private stable var __sagaData: [SagaTM.Data] = [];
    system func preupgrade() {
        __sagaData := Tools.arrayAppend(__sagaData, [_getSaga().getData()]);
        assert(List.size(__sagaData[0].actuator.tasks.0) == 0 and List.size(__sagaData[0].actuator.tasks.1) == 0);
    };
    system func postupgrade() {
        if (__sagaData.size() > 0){
            _getSaga().setData(__sagaData[0]);
            __sagaData := [];
        };
    };
    // system func heartbeat() : async () { // Interval approx. 1 second
    //     // if (count % n == 0) {
    //     // await ring();
    //     // };
    //     // count += 1;
    // }; 

};