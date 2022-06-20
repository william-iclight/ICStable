import List "mo:base/List";
import Time "mo:base/Time";
import Result "mo:base/Result";
import DRC20 "DRC20";

module {
    public type Config = {
        DUSD: Principal;
        ICL: Principal;
        ICORACLE: Principal;
        ORACLE_INTERVAL: Nat; // seconds
        LIQUIDATION_INTERVAL: Nat; // seconds
        ASSESSING_INTERVAL: Nat; // seconds 8h
        DEBT_CEILING: Nat; //DUSD per borrower
        DEBT_FLOOR: Nat; //DUSD per borrower
        INIT_COLL_RATIO: Nat; // ‱ permyriad = Collateral*factor / DebtDUSD * 10000
        MIN_COLL_RATIO: Nat; // ‱ permyriad = (Collateral*factor-STABILITY_FEE) / DebtDUSD * 10000
        INIT_STABILITY_FEE: Nat; // ‱ permyriad APY
        LIQUIDATION_FEE: Nat; // ‱ permyriad = Penalty / Collateral * 10000
    };
    public type ConfigRequest = {
        ICORACLE: ?Principal;
        ORACLE_INTERVAL: ?Nat; // seconds
        LIQUIDATION_INTERVAL: ?Nat; // seconds
        ASSESSING_INTERVAL: ?Nat; // seconds
        DEBT_CEILING: ?Nat; //DUSD per borrower
        DEBT_FLOOR: ?Nat; //DUSD per borrower
        INIT_COLL_RATIO: ?Nat; // ‱ permyriad = Collateral*factor / DebtDUSD * 10000
        MIN_COLL_RATIO: ?Nat; // ‱ permyriad = (Collateral*factor-STABILITY_FEE) / DebtDUSD * 10000
        INIT_STABILITY_FEE: ?Nat; // ‱ permyriad APY
        LIQUIDATION_FEE: ?Nat; // ‱ permyriad = Penalty / Collateral * 10000
    };
    public type Permyriad = Nat; // ‱ permyriad
    public type AccountId = Blob;
    public type Address = Text;
    public type Timestamp = Nat; // seconds
    public type Price = (ts: Timestamp, ratio: Nat, decimals: Nat);
    public type TokenId = Principal;
    public type TokenStd = { #icp; #cycles; #drc20; #dip20; #dft; #other: Text; };
    public type TokenSymbol = Text;
    public type TokenInfo = {
        tokenId: TokenId; 
        symbol: TokenSymbol; 
        std: TokenStd;
        decimals: Nat8;
        gasToken: Nat;
        gasCycles: Nat;
    };
    public type Balance = {
        balance: Nat; 
        rewards: List.List<(TokenId, Nat)>; 
        timestamp: Timestamp; 
    };
    public type CollShares = Nat;
    public type CollInfo = {
        swapPair: (Principal, {#token0; #token1});
        mktSid: Nat;
        dexSid: Nat;
        factor: Nat; // % permyriad
        totalCeiling: Nat; // Collateral
        lpDiscountRate: Nat; // % permyriad  max:2000 min:0
    };
    public type CollInfoRequest = {
        tokenId: Principal;
        swapPair: ?(Principal, {#token0; #token1});
        mktSid: ?Nat;
        dexSid: ?Nat;
        factor: ?Nat; // % permyriad
        totalCeiling: ?Nat; // Collateral
        lpDiscountRate: ?Nat; // % permyriad  max:2000 min:0
    };
    public type Yield = { // rate = accrued / shares * 10**decimals
        accrued: Nat;
        shares: Nat;   
        unitValue: Nat; // per 10**decimals shares
        timestamp: Timestamp; // seconds
        isClosed: Bool;
    };
    public type CallbackLog = (Principal, DRC20.TxnRecord);
    public type AssetResponse = {tokenId: TokenId; symbol: Text; balance: Nat; value: Nat};
    public type StatsResponse = {
        supply: Nat; // DUSD
        assetTotalValue: Nat; // DUSD
        assets: [(asset: AssetResponse, shares: Nat)];
        reserve: Int; // DUSD
        liquidity: Nat;  // DUSD
        dpCount: Nat;
        openingDpCount: Nat;
    };
    public type Dpid = Nat;
    public type Txid = Blob;
    public type Nonce = Nat;
    public type Sa = [Nat8];
    public type Data = Blob;
    public type CollValues = (tokenId: TokenId, cAmount: Nat, cShares: CollShares);
    public type Action = {#Opening; #Adding; #Removing; #Borrowing; #Closing; #Liquidating; #Other: Text;};
    public type Status = {#Prepared; #Cancelled; #Opening; #Closing; #Closed; };
    public type OperationType = {#Deposit; #Withdraw; #Mint; #Burn; #Borrow; #Lend; #Stake; #Swap; #AddLiquidity; #RemoveLiquidity; #Claim; };
    public type ClosingType = {#Payback; #Liquidate; };
    public type ChargeMethod = {#DUSD; #ICL; };
    public type DebtPosition = {
        borrower: AccountId;
        principalId: ?Principal;
        debt: Nat; // DUSD
        collaterals: [CollValues];
        doing: ?(Nat, Action, TxnRecord); // SagaTM.Toid
        status: Status;
        receivable: Nat; // DUSD
        timestamp: Timestamp; // updated
    };
    public type BalanceChange = {
        #DebitRecord: Nat;
        #CreditRecord: Nat;
        #NoChange;
    };
    public type TxnRecord = {
        txid: Txid;
        accountId: AccountId;
        index: Nat; // dpid
        nonce: Nat;
        operations: [(OperationType, TokenId, ?BalanceChange)];
        time: Time.Time;
        data: ?Blob;
    };
    public type DebtPositionLog = {
        borrower: AccountId;
        debtPeak: Nat;
        status: Status;
        transactions: [(Nat, Action, TxnRecord)]; // SagaTM.Toid
        closingType: ?ClosingType;
        stabilityCosts: Nat; // DUSD
        liquidationPenalty: [(TokenId, Nat)]; // Collateral
        openingTime: Timestamp; 
        updatedTime: Timestamp;
    };
    public type TxnResult = Result.Result<{   //<#ok, #err> 
        dpid: Dpid;
        txid: Txid;
    }, {
        code: {
            #NonceError;
            #InvalidAmount;
            #TransferException;
            #TransactionBlocking;
            #ReachedCollateralCeiling;
            #UnavailableOracle;
            #UndefinedError;
        };
        message: Text;
    }>;
    public type TrieList<K, V> = {data: [(K, V)]; total: Nat; totalPage: Nat; };
};