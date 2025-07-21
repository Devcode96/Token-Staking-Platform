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