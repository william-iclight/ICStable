/**
 * Module     : DeSwap.mo
 * Author     : ICLighthouse Team
 * Stability  : Experimental
 * Description: DeSwap Token/ICP Dex (OrderBook).
 * Refers     : https://github.com/iclighthouse/
 */

import Time "mo:base/Time";
import Result "mo:base/Result";
import OrderBook "OrderBook";
import DRC205 "DRC205";

module {
    public type AccountId = Blob;
    public type Address = Text;
    public type Txid = Blob;
    public type Toid = Nat;
    public type Amount = Nat;
    public type Sa = [Nat8];
    public type Nonce = Nat;
    public type Data = Blob;
    public type Timestamp = Nat;
    public type IcpE8s = Nat;
    public type TokenStd = DRC205.TokenStd;
    public type TokenType = {
        #Cycles;
        #Icp;
        #Token: Principal;
    };
    //type OrderType = { #Make; #Take; };
    public type OperationType = {
        #AddLiquidity;
        #RemoveLiquidity;
        #Claim;
        #Swap;
    };
    public type BalanceChange = OrderBook.BalanceChange;
    public type OrderSide = OrderBook.OrderSide;
    public type OrderType = OrderBook.OrderType;
    public type OrderPrice = OrderBook.OrderPrice;
    public type TradingStatus = { #Todo; #Pending; #Closed; #Cancelled; };
    public type OrderFilled = OrderBook.OrderFilled;
    public type TradingOrder = {
        account: AccountId;
        txid: Txid;
        orderType: OrderType;
        orderPrice: OrderPrice;
        time: Time.Time;
        expiration: Time.Time;
        toids: [Toid];
        remaining: OrderPrice;
        refund: (token0: Nat, token1: Nat, toid: Nat);
        filled: [OrderFilled];
        status: TradingStatus;
        gas : { gas0: Nat; gas1: Nat; };
        fee : { fee0: Nat; fee1: Nat; };
        index : Nat;
        nonce: Nat;
        data: ?Blob;
    };
    public type FeeBalance = {
        value0: Amount;
        value1: Amount;
    };
    public type FeeStatus = {
        feeRate: Float;
        feeBalance: FeeBalance;
        totalFee: FeeBalance;
    };
    public type DexSetting = {
        UNIT_SIZE: Nat; // 1000000 token smallest units
        ICP_FEE: IcpE8s; // 10000 E8s
        TRADING_FEE: Nat; // /1000000   value 5000 means 0.5%
        FEE_TO: AccountId;
    };
    public type DexConfig = {
        UNIT_SIZE: ?Nat;
        ICP_FEE: ?IcpE8s;
    };
    public type Vol = { value0: Amount; value1: Amount; };
    public type PriceWeighted = {
        token0TimeWeighted: Nat;
        token1TimeWeighted: Nat;
        updateTime: Timestamp; 
    };
    public type Liquidity = {
        value0: Amount;
        value1: Amount;
        shares: Amount;
        shareWeighted: { shareTimeWeighted: Nat; updateTime: Timestamp; };
        unitValue: (value0: Amount, value1: Amount);
        vol: Vol;
        priceWeighted: PriceWeighted;
        swapCount: Nat64;
    };
    public type TradingResult = Result.Result<{   //<#ok, #err> 
        txid: Txid;
        filled : [OrderFilled];
        status : TradingStatus;
    }, {
        code: {
            #NonceError;
            #InvalidAmount;
            #InsufficientBalance;
            #TransferException;
            #UnacceptableVolatility;
            #TransactionBlocking;
            #UndefinedError;
        };
        message: Text;
    }>;
    public type InitArgs = {
        name: Text;
        token: Principal;
        unitSize: Nat;
        owner: ?Principal;
    };
    public type TrieList<K, V> = {data: [(K, V)]; total: Nat; totalPage: Nat; };
    public type Self = actor {
        create : shared (_sa: ?Sa) -> async (Text, Nat); // (TxAccount, Nonce)
        trade : shared (_nonce: ?Nat, _order: OrderPrice, _orderType: OrderType, _expiration: ?Int, _sa: ?Sa, _data: ?Data) -> async TradingResult;
        cancel : shared (_nonce: Nat, _sa: ?Sa) -> async ();
        cancel2 : shared (_txid: Txid, _sa: ?Sa) -> async ();
        fallback : shared (_nonce: Nat, _sa: ?Sa) -> async Bool;
        fallback2 : shared (_txid: Txid, _sa: ?Sa) -> async Bool;
        pending : shared query (_account: ?Address, _page: ?Nat, _size: ?Nat) -> async TrieList<Txid, TradingOrder>;
        level10 : shared query () -> async {ask: [OrderPrice]; bid: [OrderPrice]};
        level50 : shared query () -> async {ask: [OrderPrice]; bid: [OrderPrice]};
        name : shared query () -> async Text;
        version : shared query () -> async Text;
        token0 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        token1 : shared query () -> async (DRC205.TokenType, ?TokenStd);
        count : shared query (_account: ?Address) -> async Nat;
        feeStatus : shared query () -> async FeeStatus;
        liquidity : shared query (_account: ?Address) -> async Liquidity;
    };
    public type DRC205 = actor {
        drc205_canisterId : shared query () -> async Principal;
        drc205_events : shared query (_account: ?DRC205.Address) -> async [DRC205.TxnRecord];
        drc205_txn : shared query (_txid: DRC205.Txid) -> async (txn: ?DRC205.TxnRecord);
        drc205_txn2 : shared (_txid: DRC205.Txid) -> async (txn: ?DRC205.TxnRecord);
    };
 };