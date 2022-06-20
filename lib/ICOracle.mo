module {
    public type Provider = Principal;
    public type SeriesId = Nat;
    public type PeriodId = Nat; // interval: [start, end)
    public type Timestamp = Nat; // seconds
    public type SeriesInfo = {
        name: Text;
        decimals: Nat; // per 10^decimals
        interval: Nat; // seconds
        maxDevRate: Nat; // ‱ permyriad
        conRequired: Nat; // Number of confirmations required to reach consensus.
        conDuration: Nat; // seconds
        cacheDuration: Nat; // seconds
    };
    public type DataItem = { value: Nat; timestamp: Timestamp; };
    public type DataResponse = {name: Text; sid: SeriesId; decimals: Nat; data:(Timestamp, Nat)};
    public type RequestLog = {
        request: DataItem;
        provider: Principal;
        time: Timestamp;
    };
    public type Log = {
        confirmed: Bool;
        requestLogs: [RequestLog]; 
    };

    public type Self = actor {
        getSeries : shared (_sid: SeriesId, _page: ?Nat) -> async [(Timestamp, Nat)]; // 2*fee
        get : shared (_sid: SeriesId, _tsSeconds: ?Timestamp) -> async ?(Timestamp, Nat); // 1*fee
        latest : shared () -> async [DataResponse]; // 2*fee
        volatility : shared (_sid: SeriesId, _spanSeconds: Nat) -> async Float; // 3*fee
        anon_getSeries : shared query (_sid: SeriesId, _page: ?Nat) -> async [(Timestamp, Nat)]; // free for anonymous
        anon_get : shared query (_sid: SeriesId, _tsSeconds: ?Timestamp) -> async ?(Timestamp, Nat); // free for anonymous
        anon_latest : shared query () -> async [{name: Text; sid: SeriesId; decimals: Nat; data:(Timestamp, Nat)}]; // free for anonymous
        request : shared (_sid: SeriesId, _data: DataItem) -> async (confirmed: Bool);
        requestFromICSwap : shared (_sid: SeriesId, _token0: Principal, _token1: Principal) -> async ();
        requestIcpXdr : shared () -> async ();
        getSeriesInfo : shared query (_sid: SeriesId) -> async ?SeriesInfo;
        getLog : shared query (_sid: SeriesId, _tsSeconds: ?Timestamp) -> async ?Log;
        workload : shared query (_account: Provider) -> async ?(score: Nat, invalid: Nat);
    };
    
};