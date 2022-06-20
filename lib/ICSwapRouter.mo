import Time "mo:base/Time";
import Result "mo:base/Result";
import DRC205 "DRC205Types";

module {
    public type DexName = Text;
    public type TokenStd = DRC205.TokenStd; // #cycles token principal = CF canister
    public type TokenSymbol = Text;
    public type TokenInfo = (Principal, TokenSymbol, TokenStd);
    //public type Pair = (Principal, Principal);
    public type SwapCanister = Principal;
    public type PairRequest = {
        token0: TokenInfo; 
        token1: TokenInfo; 
        dexName: DexName; 
    };
    public type SwapPair = {
        token0: TokenInfo; 
        token1: TokenInfo; 
        dexName: DexName; 
        canisterId: SwapCanister;
        feeRate: Float; 
    };
    public type Txid = Blob;
    public type AccountId = Blob;
    public type Nonce = Nat;
    public type Address = Text;
    public type TxnStatus = { #Pending; #Success; #Failure; #Blocking; };
    public type TxnResult = Result.Result<{   //<#ok, #err> 
        txid: Txid;
        status: TxnStatus;
    }, {
        code: {
            #NonceError;
            #InvalidAmout;
            #UndefinedError;
        };
        message: Text;
    }>;
    public type Config = { 
        SYS_TOKEN: Principal;
        CREATION_FEE: Nat; // token
        ROUTING_FEE: Nat; // token
        DEFAULT_VOLATILITY_LIMIT: Nat; //%
    };
    public type ConfigRequest = { 
        CREATION_FEE: ?Nat; // token
        ROUTING_FEE: ?Nat; // token
        DEFAULT_VOLATILITY_LIMIT: ?Nat; //%
    };
    public type TrieList<K, V> = {data: [(K, V)]; total: Nat; totalPage: Nat; };
    public type Self = actor {
        create : shared (_pair: PairRequest) -> async (canister: SwapCanister, initialized: Bool);
        getDexList : shared query () -> async [(DexName, Principal)];
        getTokens : shared query (_dexName: ?DexName) -> async [TokenInfo];
        getCurrencies : shared query () -> async [TokenInfo];
        getPairsByToken : shared query (_token: Principal, _dexName: ?DexName) -> async [(SwapCanister, (SwapPair, Nat))];
        getPairs : shared query (_dexName: ?DexName, _page: ?Nat, _size: ?Nat) -> async TrieList<SwapCanister, (SwapPair, Nat)>;
        route : shared query (_token0: Principal, _token1: Principal, _dexName: ?DexName) -> async [(SwapCanister, (SwapPair, Nat))];
        putByDex : shared (_token0: TokenInfo, _token1: TokenInfo, _canisterId: Principal) -> async ();
        removeByDex : shared (_pairCanister: Principal) -> async ();
    };
};