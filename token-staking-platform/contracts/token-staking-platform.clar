;; Advanced Multi-Feature Staking Contract

;; ===============================
;; ERROR CONSTANTS
;; ===============================
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_CONTRACT_PAUSED (err u102))
(define-constant ERR_LOCKUP_ACTIVE (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_MIN_STAKE_NOT_MET (err u105))
(define-constant ERR_MAX_STAKE_EXCEEDED (err u106))
(define-constant ERR_POOL_NOT_FOUND (err u107))
(define-constant ERR_INSUFFICIENT_REWARDS (err u108))
(define-constant ERR_COOLDOWN_ACTIVE (err u109))
(define-constant ERR_DELEGATION_EXISTS (err u110))
(define-constant ERR_INVALID_DURATION (err u111))

;; ===============================
;; CONTRACT CONSTANTS
;; ===============================
(define-constant CONTRACT_OWNER tx-sender)
(define-constant MIN_STAKE_AMOUNT u1000000) ;; 1 STX
(define-constant MAX_STAKE_AMOUNT u100000000000) ;; 100K STX
(define-constant DEFAULT_LOCKUP_BLOCKS u144) ;; ~24 hours
(define-constant COOLDOWN_BLOCKS u72) ;; ~12 hours
(define-constant BASE_REWARD_RATE u300) ;; 3% base APR
(define-constant BONUS_RATE_MULTIPLIER u50) ;; 0.5% per additional month
(define-constant DELEGATION_FEE_RATE u1000) ;; 10% fee
(define-constant MAX_POOLS u10)

;; ===============================
;; STATE VARIABLES
;; ===============================
(define-data-var total-staked uint u0)
(define-data-var total-rewards-pool uint u0)
(define-data-var contract-paused bool false)
(define-data-var next-pool-id uint u1)
(define-data-var global-reward-multiplier uint u10000) ;; 100% = no change
(define-data-var emergency-mode bool false)

;; ===============================
;; DATA MAPS
;; ===============================

;; Enhanced user stakes with comprehensive tracking
(define-map stakes 
  { user: principal } 
  { 
    amount: uint,
    stake-block: uint,
    last-reward-claim: uint,
    lockup-end: uint,
    tier: uint,
    total-rewards-earned: uint,
    streak-bonus: uint
  }
)

;; Staking pools for different risk/reward profiles
(define-map staking-pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    min-stake: uint,
    lockup-period: uint,
    reward-rate: uint,
    total-staked: uint,
    active: bool,
    creator: principal
  }
)

;; User participation in specific pools
(define-map user-pool-stakes
  { user: principal, pool-id: uint }
  {
    amount: uint,
    stake-block: uint,
    last-claim: uint
  }
)

;; Delegation system
(define-map delegations
  { delegator: principal, validator: principal }
  {
    amount: uint,
    start-block: uint,
    fee-rate: uint
  }
)

;; Validator information
(define-map validators
  { validator: principal }
  {
    total-delegated: uint,
    commission-rate: uint,
    active: bool,
    reputation-score: uint
  }
)

;; Unstake requests (for delayed unstaking)
(define-map unstake-requests
  { user: principal, request-id: uint }
  {
    amount: uint,
    request-block: uint,
    ready-block: uint,
    processed: bool
  }
)

;; User cooldowns
(define-map user-cooldowns
  { user: principal }
  { cooldown-end: uint }
)

;; Referral system
(define-map referrals
  { referrer: principal, referee: principal }
  {
    bonus-earned: uint,
    active: bool
  }
)

;; User statistics
(define-map user-stats
  { user: principal }
  {
    total-staked-ever: uint,
    total-rewards-claimed: uint,
    stake-count: uint,
    referrals-made: uint,
    join-block: uint
  }
)

;; ===============================
;; ADMIN FUNCTIONS
;; ===============================

(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (set-emergency-mode (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set emergency-mode enabled)
    (ok true)
  )
)

(define-public (add-rewards-to-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set total-rewards-pool (+ (var-get total-rewards-pool) amount))
    (ok true)
  )
)

(define-public (set-global-reward-multiplier (multiplier uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set global-reward-multiplier multiplier)
    (ok true)
  )
)

;; ===============================
;; STAKING POOL FUNCTIONS
;; ===============================

(define-public (create-staking-pool (name (string-ascii 50)) (min-stake uint) (lockup-period uint) (reward-rate uint))
  (let ((pool-id (var-get next-pool-id)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
      (asserts! (< pool-id MAX_POOLS) ERR_MAX_STAKE_EXCEEDED)
      
      (map-set staking-pools { pool-id: pool-id } {
        name: name,
        min-stake: min-stake,
        lockup-period: lockup-period,
        reward-rate: reward-rate,
        total-staked: u0,
        active: true,
        creator: tx-sender
      })
      
      (var-set next-pool-id (+ pool-id u1))
      (ok pool-id)
    )
  )
)

(define-public (stake-in-pool (pool-id uint) (amount uint))
  (let ((pool (unwrap! (map-get? staking-pools { pool-id: pool-id }) ERR_POOL_NOT_FOUND)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
      (asserts! (get active pool) ERR_POOL_NOT_FOUND)
      (asserts! (>= amount (get min-stake pool)) ERR_MIN_STAKE_NOT_MET)
      
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      (let ((current-stake (default-to { amount: u0, stake-block: block-height, last-claim: block-height }
                                       (map-get? user-pool-stakes { user: tx-sender, pool-id: pool-id }))))
        (map-set user-pool-stakes { user: tx-sender, pool-id: pool-id } {
          amount: (+ (get amount current-stake) amount),
          stake-block: (get stake-block current-stake),
          last-claim: block-height
        })
        
        (map-set staking-pools { pool-id: pool-id } 
          (merge pool { total-staked: (+ (get total-staked pool) amount) }))
        
        (update-user-stats tx-sender amount)
        (ok true)
      )
    )
  )
)

; ===============================
;; ENHANCED STAKING FUNCTIONS
;; ===============================

(define-public (stake-with-lockup (amount uint) (lockup-months uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= amount MIN_STAKE_AMOUNT) ERR_MIN_STAKE_NOT_MET)
    (asserts! (<= amount MAX_STAKE_AMOUNT) ERR_MAX_STAKE_EXCEEDED)
    (asserts! (<= lockup-months u12) ERR_INVALID_DURATION)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (let 
      (
        (current-stake (default-to 
          { amount: u0, stake-block: block-height, last-reward-claim: block-height, 
            lockup-end: u0, tier: u1, total-rewards-earned: u0, streak-bonus: u0 }
          (map-get? stakes { user: tx-sender })
        ))
        (lockup-blocks (* lockup-months u4320)) ;; ~30 days per month
        (tier (calculate-tier (+ (get amount current-stake) amount)))
      )
      
      (map-set stakes { user: tx-sender } {
        amount: (+ (get amount current-stake) amount),
        stake-block: (if (is-eq (get amount current-stake) u0) block-height (get stake-block current-stake)),
        last-reward-claim: block-height,
        lockup-end: (+ block-height lockup-blocks),
        tier: tier,
        total-rewards-earned: (get total-rewards-earned current-stake),
        streak-bonus: (calculate-streak-bonus tx-sender)
      })
      
      (var-set total-staked (+ (var-get total-staked) amount))
      (update-user-stats tx-sender amount)
      
      (ok true)
    )
  )
)

(define-public (stake (amount uint))
  (stake-with-lockup amount u1)
)

;; ===============================
;; UNSTAKING FUNCTIONS
;; ===============================

(define-public (unstake-with-delay (amount uint))
  (let ((stake-data (unwrap! (map-get? stakes { user: tx-sender }) ERR_NOT_AUTHORIZED)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
      (asserts! (>= (get amount stake-data) amount) ERR_INSUFFICIENT_BALANCE)
      (asserts! (>= block-height (get lockup-end stake-data)) ERR_LOCKUP_ACTIVE)
      
      ;; Create unstake request
      (let ((request-id (+ block-height (get amount stake-data))))
        (map-set unstake-requests { user: tx-sender, request-id: request-id } {
          amount: amount,
          request-block: block-height,
          ready-block: (+ block-height COOLDOWN_BLOCKS),
          processed: false
        })
      )
      
      ;; Set cooldown
      (map-set user-cooldowns { user: tx-sender } { cooldown-end: (+ block-height COOLDOWN_BLOCKS) })
      
      (ok true)
    )
  )
)

(define-public (process-unstake-request (request-id uint))
  (let ((request (unwrap! (map-get? unstake-requests { user: tx-sender, request-id: request-id }) ERR_NOT_AUTHORIZED)))
    (begin
      (asserts! (not (get processed request)) ERR_NOT_AUTHORIZED)
      (asserts! (>= block-height (get ready-block request)) ERR_COOLDOWN_ACTIVE)
      
      (let ((stake-data (unwrap! (map-get? stakes { user: tx-sender }) ERR_NOT_AUTHORIZED)))
        (try! (as-contract (stx-transfer? (get amount request) tx-sender tx-sender)))
        
        (map-set stakes { user: tx-sender } 
          (merge stake-data { amount: (- (get amount stake-data) (get amount request)) }))
        
        (map-set unstake-requests { user: tx-sender, request-id: request-id }
          (merge request { processed: true }))
        
        (var-set total-staked (- (var-get total-staked) (get amount request)))
        
        (ok true)
      )
    )
  )
)

(define-public (unstake (amount uint))
  (begin
    (if (var-get emergency-mode)
      ;; Emergency unstake - immediate
      (emergency-unstake-internal amount)
      ;; Normal unstake with delay
      (unstake-with-delay amount)
    )
  )
)

;; Emergency unstake function (private)
(define-private (emergency-unstake-internal (amount uint))
  (let ((stake-data (unwrap! (map-get? stakes { user: tx-sender }) ERR_NOT_AUTHORIZED)))
    (begin
      (asserts! (>= (get amount stake-data) amount) ERR_INSUFFICIENT_BALANCE)
      (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
      
      (map-set stakes { user: tx-sender }
        (merge stake-data { amount: (- (get amount stake-data) amount) }))
      
      (var-set total-staked (- (var-get total-staked) amount))
      (ok true)
    )
  )
)

;; SECTION 4: REWARDS SYSTEM AND DELEGATION
;; Commit: "feat: implement tiered rewards system, compound staking, delegation mechanism, and referral program"

;; ===============================
;; REWARDS FUNCTIONS
;; ===============================

(define-public (claim-rewards)
  (let ((stake-data (unwrap! (map-get? stakes { user: tx-sender }) ERR_NOT_AUTHORIZED)))
    (let ((rewards (calculate-user-rewards tx-sender)))
      (begin
        (asserts! (> rewards u0) ERR_INSUFFICIENT_REWARDS)
        (asserts! (>= (var-get total-rewards-pool) rewards) ERR_INSUFFICIENT_REWARDS)
        
        (try! (as-contract (stx-transfer? rewards tx-sender tx-sender)))
        
        (map-set stakes { user: tx-sender }
          (merge stake-data { 
            last-reward-claim: block-height,
            total-rewards-earned: (+ (get total-rewards-earned stake-data) rewards)
          }))
        
        (var-set total-rewards-pool (- (var-get total-rewards-pool) rewards))
        (update-user-reward-stats tx-sender rewards)
        
        (ok rewards)
      )
    )
  )
)

(define-public (compound-rewards)
  (let ((rewards (calculate-user-rewards tx-sender)))
    (begin
      (asserts! (> rewards u0) ERR_INSUFFICIENT_REWARDS)
      
      ;; Claim rewards internally
      (let ((stake-data (unwrap! (map-get? stakes { user: tx-sender }) ERR_NOT_AUTHORIZED)))
        (map-set stakes { user: tx-sender }
          (merge stake-data {
            amount: (+ (get amount stake-data) rewards),
            last-reward-claim: block-height,
            total-rewards-earned: (+ (get total-rewards-earned stake-data) rewards)
          }))
        
        (var-set total-staked (+ (var-get total-staked) rewards))
        (var-set total-rewards-pool (- (var-get total-rewards-pool) rewards))
        
        (ok rewards)
      )
    )
  )
)

;; ===============================
;; DELEGATION FUNCTIONS
;; ===============================

(define-public (delegate-stake (validator principal) (amount uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR_CONTRACT_PAUSED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (is-none (map-get? delegations { delegator: tx-sender, validator: validator })) ERR_DELEGATION_EXISTS)
    
    (let ((stake-data (unwrap! (map-get? stakes { user: tx-sender }) ERR_NOT_AUTHORIZED)))
      (begin
        (asserts! (>= (get amount stake-data) amount) ERR_INSUFFICIENT_BALANCE)
        
        (map-set delegations { delegator: tx-sender, validator: validator } {
          amount: amount,
          start-block: block-height,
          fee-rate: DELEGATION_FEE_RATE
        })
        
        ;; Update validator stats
        (let ((validator-data (default-to 
          { total-delegated: u0, commission-rate: DELEGATION_FEE_RATE, active: true, reputation-score: u100 }
          (map-get? validators { validator: validator }))))
          (map-set validators { validator: validator }
            (merge validator-data { total-delegated: (+ (get total-delegated validator-data) amount) }))
        )
        
        (ok true)
      )
    )
  )
)

(define-public (undelegate-stake (validator principal))
  (let ((delegation (unwrap! (map-get? delegations { delegator: tx-sender, validator: validator }) ERR_NOT_AUTHORIZED)))
    (begin
      (map-delete delegations { delegator: tx-sender, validator: validator })
      
      ;; Update validator stats
      (let ((validator-data (unwrap! (map-get? validators { validator: validator }) ERR_NOT_AUTHORIZED)))
        (map-set validators { validator: validator }
          (merge validator-data { total-delegated: (- (get total-delegated validator-data) (get amount delegation)) }))
      )
      
      (ok true)
    )
  )
)

;; ===============================
;; REFERRAL FUNCTIONS
;; ===============================

(define-public (stake-with-referral (amount uint) (referrer principal))
  (begin
    (try! (stake amount))
    
    ;; Add referral bonus (5% of stake amount)
    (let ((bonus (/ (* amount u500) u10000)))
      (map-set referrals { referrer: referrer, referee: tx-sender } {
        bonus-earned: bonus,
        active: true
      })
      
      ;; Transfer bonus to referrer
      (and (> bonus u0) 
           (>= (var-get total-rewards-pool) bonus)
           (is-ok (as-contract (stx-transfer? bonus tx-sender referrer))))
    )
    
    (ok true)
  )
)