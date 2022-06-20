import Time "mo:base/Time";
import Result "mo:base/Result";
import DRC205 "DRC205";

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
    public type TrieList<K, V> = {data: [(K, V)]; total: Nat; totalPage: Nat; };
    public type Self = actor {
        create : shared (_token: ?Principal) -> async (canister: SwapCanister);
        getTokens : shared query () -> async [TokenInfo];
        getPairs : shared query (_page: ?Nat, _size: ?Nat) -> async TrieList<SwapCanister, SwapPair>;
        getPairsByToken : shared query (_token: Principal) -> async [(SwapCanister, SwapPair)];
    };
};