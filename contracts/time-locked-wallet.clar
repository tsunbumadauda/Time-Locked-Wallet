(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-still-locked (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-unlock-height (err u105))
(define-constant err-unauthorized (err u106))

(define-map wallets
  { wallet-id: uint }
  {
    owner: principal,
    balance: uint,
    unlock-height: uint,
    created-at: uint
  }
)

(define-map user-wallets
  { user: principal }
  { wallet-count: uint }
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
        created-at: current-height
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
      (merge wallet { balance: (+ (get balance wallet) amount) })
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
      (merge wallet { balance: (- (get balance wallet) amount) })
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
      (merge wallet { balance: u0 })
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
      (merge wallet { unlock-height: new-unlock-height })
    )
    
    (ok new-unlock-height)
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

(define-read-only (is-wallet-owner (wallet-id uint) (user principal))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (is-eq (get owner wallet) user)
    false
  )
)
