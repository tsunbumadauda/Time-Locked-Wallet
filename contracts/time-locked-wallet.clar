(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-still-locked (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-unlock-height (err u105))
(define-constant err-unauthorized (err u106))
(define-constant err-guardian-exists (err u107))
(define-constant err-not-guardian (err u108))
(define-constant err-owner-still-active (err u109))
(define-constant err-recovery-not-ready (err u110))
(define-constant err-recovery-already-initiated (err u111))

(define-map wallets
  { wallet-id: uint }
  {
    owner: principal,
    balance: uint,
    unlock-height: uint,
    created-at: uint,
    last-activity: uint,
    recovery-delay: uint
  }
)

(define-map user-wallets
  { user: principal }
  { wallet-count: uint }
)

(define-map recovery-guardians
  { wallet-id: uint, guardian: principal }
  { authorized-at: uint, is-active: bool }
)

(define-map recovery-requests
  { wallet-id: uint }
  { guardian: principal, initiated-at: uint, recovery-delay: uint }
)

(define-data-var next-wallet-id uint u1)

(define-public (create-wallet (unlock-height uint))
  (let (
    (wallet-id (var-get next-wallet-id))
    (current-height stacks-block-height)
  )
    (asserts! (> unlock-height current-height) err-invalid-unlock-height)
    (asserts! (is-none (map-get? wallets { wallet-id: wallet-id })) err-already-exists)
    
    (map-set wallets
      { wallet-id: wallet-id }
      {
        owner: tx-sender,
        balance: u0,
        unlock-height: unlock-height,
        created-at: current-height,
        last-activity: current-height,
        recovery-delay: u10080
      }
    )
    
    (map-set user-wallets
      { user: tx-sender }
      { wallet-count: (+ (get-user-wallet-count tx-sender) u1) }
    )
    
    (var-set next-wallet-id (+ wallet-id u1))
    (ok wallet-id)
  )
)

(define-public (deposit (wallet-id uint) (amount uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
  )
    (asserts! (> amount u0) err-insufficient-balance)
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        balance: (+ (get balance wallet) amount),
        last-activity: stacks-block-height
      })
    )
    
    (ok amount)
  )
)

(define-public (withdraw (wallet-id uint) (amount uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (current-height stacks-block-height)
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (>= current-height (get unlock-height wallet)) err-still-locked)
    (asserts! (>= (get balance wallet) amount) err-insufficient-balance)
    (asserts! (> amount u0) err-insufficient-balance)
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        balance: (- (get balance wallet) amount),
        last-activity: stacks-block-height
      })
    )
    
    (ok amount)
  )
)

(define-public (withdraw-all (wallet-id uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (current-height stacks-block-height)
    (balance (get balance wallet))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (>= current-height (get unlock-height wallet)) err-still-locked)
    (asserts! (> balance u0) err-insufficient-balance)
    
    (try! (as-contract (stx-transfer? balance tx-sender tx-sender)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        balance: u0,
        last-activity: stacks-block-height
      })
    )
    
    (ok balance)
  )
)

(define-public (extend-lock (wallet-id uint) (new-unlock-height uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (current-unlock-height (get unlock-height wallet))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (> new-unlock-height current-unlock-height) err-invalid-unlock-height)
    (asserts! (> new-unlock-height stacks-block-height) err-invalid-unlock-height)
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        unlock-height: new-unlock-height,
        last-activity: stacks-block-height
      })
    )
    
    (ok new-unlock-height)
  )
)

(define-public (set-recovery-guardian (wallet-id uint) (guardian principal))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (is-none (map-get? recovery-guardians { wallet-id: wallet-id, guardian: guardian })) err-guardian-exists)
    
    (map-set recovery-guardians
      { wallet-id: wallet-id, guardian: guardian }
      { authorized-at: stacks-block-height, is-active: true }
    )
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { last-activity: stacks-block-height })
    )
    
    (ok true)
  )
)

(define-public (remove-recovery-guardian (wallet-id uint) (guardian principal))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (is-some (map-get? recovery-guardians { wallet-id: wallet-id, guardian: guardian })) err-not-found)
    
    (map-delete recovery-guardians { wallet-id: wallet-id, guardian: guardian })
    (map-delete recovery-requests { wallet-id: wallet-id })
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { last-activity: stacks-block-height })
    )
    
    (ok true)
  )
)

(define-public (initiate-emergency-recovery (wallet-id uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (guardian-info (unwrap! (map-get? recovery-guardians { wallet-id: wallet-id, guardian: tx-sender }) err-not-guardian))
    (inactivity-period (- stacks-block-height (get last-activity wallet)))
  )
    (asserts! (get is-active guardian-info) err-not-guardian)
    (asserts! (>= inactivity-period (get recovery-delay wallet)) err-owner-still-active)
    (asserts! (is-none (map-get? recovery-requests { wallet-id: wallet-id })) err-recovery-already-initiated)
    
    (map-set recovery-requests
      { wallet-id: wallet-id }
      { 
        guardian: tx-sender,
        initiated-at: stacks-block-height,
        recovery-delay: u1440
      }
    )
    
    (ok true)
  )
)

(define-public (execute-emergency-recovery (wallet-id uint) (recovery-address principal))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (recovery-request (unwrap! (map-get? recovery-requests { wallet-id: wallet-id }) err-not-found))
    (current-height stacks-block-height)
    (recovery-ready (>= (- current-height (get initiated-at recovery-request)) (get recovery-delay recovery-request)))
    (wallet-balance (get balance wallet))
  )
    (asserts! (is-eq (get guardian recovery-request) tx-sender) err-unauthorized)
    (asserts! recovery-ready err-recovery-not-ready)
    (asserts! (> wallet-balance u0) err-insufficient-balance)
    
    (try! (as-contract (stx-transfer? wallet-balance tx-sender recovery-address)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { balance: u0 })
    )
    
    (map-delete recovery-requests { wallet-id: wallet-id })
    
    (ok wallet-balance)
  )
)

(define-public (cancel-recovery-request (wallet-id uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (is-some (map-get? recovery-requests { wallet-id: wallet-id })) err-not-found)
    
    (map-delete recovery-requests { wallet-id: wallet-id })
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { last-activity: stacks-block-height })
    )
    
    (ok true)
  )
)

(define-public (delete-empty-wallet (wallet-id uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (is-eq (get balance wallet) u0) err-insufficient-balance)
    
    (map-delete wallets { wallet-id: wallet-id })
    
    (map-set user-wallets
      { user: tx-sender }
      { wallet-count: (- (get-user-wallet-count tx-sender) u1) }
    )
    
    (ok true)
  )
)

(define-read-only (get-wallet (wallet-id uint))
  (map-get? wallets { wallet-id: wallet-id })
)

(define-read-only (get-wallet-balance (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (some (get balance wallet))
    none
  )
)

(define-read-only (get-wallet-unlock-height (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (some (get unlock-height wallet))
    none
  )
)

(define-read-only (is-wallet-unlocked (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (>= stacks-block-height (get unlock-height wallet))
    false
  )
)

(define-read-only (get-blocks-until-unlock (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (if (>= stacks-block-height (get unlock-height wallet))
        u0
        (- (get unlock-height wallet) stacks-block-height)
      )
    u0
  )
)

(define-read-only (get-user-wallet-count (user principal))
  (default-to u0 (get wallet-count (map-get? user-wallets { user: user })))
)

(define-read-only (get-current-stacks-block-height)
  stacks-block-height
)

(define-read-only (get-next-wallet-id)
  (var-get next-wallet-id)
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-recovery-guardian (wallet-id uint) (guardian principal))
  (map-get? recovery-guardians { wallet-id: wallet-id, guardian: guardian })
)

(define-read-only (get-recovery-request (wallet-id uint))
  (map-get? recovery-requests { wallet-id: wallet-id })
)

(define-read-only (is-recovery-ready (wallet-id uint))
  (match (map-get? recovery-requests { wallet-id: wallet-id })
    request (>= (- stacks-block-height (get initiated-at request)) (get recovery-delay request))
    false
  )
)

(define-read-only (get-owner-inactivity-period (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (- stacks-block-height (get last-activity wallet))
    u0
  )
)

(define-read-only (can-initiate-recovery (wallet-id uint) (guardian principal))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (let (
        (guardian-info (map-get? recovery-guardians { wallet-id: wallet-id, guardian: guardian }))
        (inactivity-period (- stacks-block-height (get last-activity wallet)))
      )
        (and 
          (is-some guardian-info)
          (get is-active (unwrap-panic guardian-info))
          (>= inactivity-period (get recovery-delay wallet))
          (is-none (map-get? recovery-requests { wallet-id: wallet-id }))
        )
      )
    false
  )
)

(define-read-only (is-wallet-owner (wallet-id uint) (user principal))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (is-eq (get owner wallet) user)
    false
  )
)
