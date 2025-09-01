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
(define-constant err-insufficient-approvals (err u112))
(define-constant err-already-approved (err u113))
(define-constant err-not-co-owner (err u114))
(define-constant err-invalid-threshold (err u115))
(define-constant err-cannot-remove-self (err u116))
(define-constant err-vesting-not-enabled (err u117))
(define-constant err-cliff-not-reached (err u118))
(define-constant err-exceeds-vested-amount (err u119))
(define-constant err-invalid-vesting-duration (err u120))

(define-map wallets
  { wallet-id: uint }
  {
    owner: principal,
    balance: uint,
    unlock-height: uint,
    created-at: uint,
    last-activity: uint,
    recovery-delay: uint,
    is-multisig: bool,
    approval-threshold: uint,
    total-owners: uint,
    has-vesting: bool,
    vesting-start: uint,
    vesting-duration: uint,
    cliff-period: uint,
    claimed-amount: uint
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

(define-map wallet-co-owners
  { wallet-id: uint, owner: principal }
  { added-at: uint, is-active: bool }
)

(define-map pending-approvals
  { wallet-id: uint, operation-id: uint }
  { operation-type: (string-ascii 20), target-amount: uint, approvals: (list 20 principal), created-at: uint }
)

(define-data-var next-wallet-id uint u1)
(define-data-var next-operation-id uint u1)

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
        recovery-delay: u10080,
        is-multisig: false,
        approval-threshold: u1,
        total-owners: u1,
        has-vesting: false,
        vesting-start: u0,
        vesting-duration: u0,
        cliff-period: u0,
        claimed-amount: u0
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
    (asserts! (or (is-eq (get owner wallet) tx-sender) (is-co-owner wallet-id tx-sender)) err-unauthorized)
    
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
    
    (if (get has-vesting wallet)
      (let (
        (available-amount (calculate-vested-amount wallet-id))
        (unclaimed-amount (- available-amount (get claimed-amount wallet)))
      )
        (asserts! (>= unclaimed-amount amount) err-exceeds-vested-amount)
      )
      true
    )
    
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        balance: (- (get balance wallet) amount),
        last-activity: stacks-block-height,
        claimed-amount: (if (get has-vesting wallet) 
          (+ (get claimed-amount wallet) amount) 
          (get claimed-amount wallet))
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

(define-public (create-multisig-wallet (unlock-height uint) (approval-threshold uint))
  (let (
    (wallet-id (var-get next-wallet-id))
    (current-height stacks-block-height)
  )
    (asserts! (> unlock-height current-height) err-invalid-unlock-height)
    (asserts! (> approval-threshold u0) err-invalid-threshold)
    (asserts! (<= approval-threshold u20) err-invalid-threshold)
    (asserts! (is-none (map-get? wallets { wallet-id: wallet-id })) err-already-exists)
    
    (map-set wallets
      { wallet-id: wallet-id }
      {
        owner: tx-sender,
        balance: u0,
        unlock-height: unlock-height,
        created-at: current-height,
        last-activity: current-height,
        recovery-delay: u10080,
        is-multisig: true,
        approval-threshold: approval-threshold,
        total-owners: u1,
        has-vesting: false,
        vesting-start: u0,
        vesting-duration: u0,
        cliff-period: u0,
        claimed-amount: u0
      }
    )
    
    (map-set wallet-co-owners
      { wallet-id: wallet-id, owner: tx-sender }
      { added-at: current-height, is-active: true }
    )
    
    (map-set user-wallets
      { user: tx-sender }
      { wallet-count: (+ (get-user-wallet-count tx-sender) u1) }
    )
    
    (var-set next-wallet-id (+ wallet-id u1))
    (ok wallet-id)
  )
)

(define-public (add-co-owner (wallet-id uint) (new-owner principal))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (get is-multisig wallet) err-unauthorized)
    (asserts! (< (get total-owners wallet) u20) err-invalid-threshold)
    (asserts! (is-none (map-get? wallet-co-owners { wallet-id: wallet-id, owner: new-owner })) err-already-exists)
    
    (map-set wallet-co-owners
      { wallet-id: wallet-id, owner: new-owner }
      { added-at: stacks-block-height, is-active: true }
    )
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        total-owners: (+ (get total-owners wallet) u1),
        last-activity: stacks-block-height
      })
    )
    
    (ok true)
  )
)

(define-public (remove-co-owner (wallet-id uint) (remove-owner principal))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (get is-multisig wallet) err-unauthorized)
    (asserts! (not (is-eq remove-owner tx-sender)) err-cannot-remove-self)
    (asserts! (is-some (map-get? wallet-co-owners { wallet-id: wallet-id, owner: remove-owner })) err-not-found)
    (asserts! (> (get total-owners wallet) (get approval-threshold wallet)) err-invalid-threshold)
    
    (map-delete wallet-co-owners { wallet-id: wallet-id, owner: remove-owner })
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        total-owners: (- (get total-owners wallet) u1),
        last-activity: stacks-block-height
      })
    )
    
    (ok true)
  )
)

(define-public (propose-withdrawal (wallet-id uint) (amount uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (operation-id (var-get next-operation-id))
  )
    (asserts! (get is-multisig wallet) err-unauthorized)
    (asserts! (or (is-eq (get owner wallet) tx-sender) (is-co-owner wallet-id tx-sender)) err-unauthorized)
    (asserts! (> amount u0) err-insufficient-balance)
    (asserts! (>= (get balance wallet) amount) err-insufficient-balance)
    
    (map-set pending-approvals
      { wallet-id: wallet-id, operation-id: operation-id }
      { 
        operation-type: "withdrawal",
        target-amount: amount,
        approvals: (list tx-sender),
        created-at: stacks-block-height
      }
    )
    
    (var-set next-operation-id (+ operation-id u1))
    (ok operation-id)
  )
)

(define-public (approve-operation (wallet-id uint) (operation-id uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (operation (unwrap! (map-get? pending-approvals { wallet-id: wallet-id, operation-id: operation-id }) err-not-found))
    (current-approvals (get approvals operation))
  )
    (asserts! (get is-multisig wallet) err-unauthorized)
    (asserts! (or (is-eq (get owner wallet) tx-sender) (is-co-owner wallet-id tx-sender)) err-unauthorized)
    (asserts! (is-none (index-of current-approvals tx-sender)) err-already-approved)
    
    (let (
      (updated-approvals (unwrap! (as-max-len? (append current-approvals tx-sender) u20) err-invalid-threshold))
    )
      (map-set pending-approvals
        { wallet-id: wallet-id, operation-id: operation-id }
        (merge operation { approvals: updated-approvals })
      )
      
      (ok (len updated-approvals))
    )
  )
)

(define-public (execute-multisig-withdrawal (wallet-id uint) (operation-id uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (operation (unwrap! (map-get? pending-approvals { wallet-id: wallet-id, operation-id: operation-id }) err-not-found))
    (current-height stacks-block-height)
    (approval-count (len (get approvals operation)))
    (withdrawal-amount (get target-amount operation))
  )
    (asserts! (get is-multisig wallet) err-unauthorized)
    (asserts! (>= current-height (get unlock-height wallet)) err-still-locked)
    (asserts! (>= approval-count (get approval-threshold wallet)) err-insufficient-approvals)
    (asserts! (>= (get balance wallet) withdrawal-amount) err-insufficient-balance)
    (asserts! (is-eq (get operation-type operation) "withdrawal") err-unauthorized)
    
    (try! (as-contract (stx-transfer? withdrawal-amount tx-sender tx-sender)))
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        balance: (- (get balance wallet) withdrawal-amount),
        last-activity: current-height
      })
    )
    
    (map-delete pending-approvals { wallet-id: wallet-id, operation-id: operation-id })
    
    (ok withdrawal-amount)
  )
)

(define-public (create-vesting-wallet (unlock-height uint) (vesting-duration uint) (cliff-period uint))
  (let (
    (wallet-id (var-get next-wallet-id))
    (current-height stacks-block-height)
  )
    (asserts! (> unlock-height current-height) err-invalid-unlock-height)
    (asserts! (> vesting-duration u0) err-invalid-vesting-duration)
    (asserts! (<= cliff-period vesting-duration) err-invalid-vesting-duration)
    (asserts! (is-none (map-get? wallets { wallet-id: wallet-id })) err-already-exists)
    
    (map-set wallets
      { wallet-id: wallet-id }
      {
        owner: tx-sender,
        balance: u0,
        unlock-height: unlock-height,
        created-at: current-height,
        last-activity: current-height,
        recovery-delay: u10080,
        is-multisig: false,
        approval-threshold: u1,
        total-owners: u1,
        has-vesting: true,
        vesting-start: unlock-height,
        vesting-duration: vesting-duration,
        cliff-period: cliff-period,
        claimed-amount: u0
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

(define-public (claim-vested-amount (wallet-id uint) (amount uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (current-height stacks-block-height)
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (get has-vesting wallet) err-vesting-not-enabled)
    (asserts! (>= current-height (+ (get vesting-start wallet) (get cliff-period wallet))) err-cliff-not-reached)
    (asserts! (> amount u0) err-insufficient-balance)
    (asserts! (>= (get balance wallet) amount) err-insufficient-balance)
    
    (let (
      (vested-amount (calculate-vested-amount wallet-id))
      (available-amount (- vested-amount (get claimed-amount wallet)))
    )
      (asserts! (>= available-amount amount) err-exceeds-vested-amount)
      
      (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
      
      (map-set wallets
        { wallet-id: wallet-id }
        (merge wallet { 
          balance: (- (get balance wallet) amount),
          claimed-amount: (+ (get claimed-amount wallet) amount),
          last-activity: current-height
        })
      )
      
      (ok amount)
    )
  )
)

(define-public (update-vesting-schedule (wallet-id uint) (new-vesting-duration uint) (new-cliff-period uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (current-height stacks-block-height)
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (get has-vesting wallet) err-vesting-not-enabled)
    (asserts! (< current-height (get vesting-start wallet)) err-invalid-vesting-duration)
    (asserts! (> new-vesting-duration u0) err-invalid-vesting-duration)
    (asserts! (<= new-cliff-period new-vesting-duration) err-invalid-vesting-duration)
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        vesting-duration: new-vesting-duration,
        cliff-period: new-cliff-period,
        last-activity: current-height
      })
    )
    
    (ok true)
  )
)

(define-public (disable-vesting (wallet-id uint))
  (let (
    (wallet (unwrap! (map-get? wallets { wallet-id: wallet-id }) err-not-found))
    (current-height stacks-block-height)
  )
    (asserts! (is-eq (get owner wallet) tx-sender) err-unauthorized)
    (asserts! (get has-vesting wallet) err-vesting-not-enabled)
    (asserts! (< current-height (get vesting-start wallet)) err-invalid-vesting-duration)
    
    (map-set wallets
      { wallet-id: wallet-id }
      (merge wallet { 
        has-vesting: false,
        vesting-start: u0,
        vesting-duration: u0,
        cliff-period: u0,
        claimed-amount: u0,
        last-activity: current-height
      })
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

(define-read-only (get-co-owner-info (wallet-id uint) (owner principal))
  (map-get? wallet-co-owners { wallet-id: wallet-id, owner: owner })
)

(define-read-only (get-pending-operation (wallet-id uint) (operation-id uint))
  (map-get? pending-approvals { wallet-id: wallet-id, operation-id: operation-id })
)

(define-read-only (is-co-owner (wallet-id uint) (user principal))
  (match (map-get? wallet-co-owners { wallet-id: wallet-id, owner: user })
    co-owner-info (get is-active co-owner-info)
    false
  )
)

(define-read-only (get-approval-count (wallet-id uint) (operation-id uint))
  (match (map-get? pending-approvals { wallet-id: wallet-id, operation-id: operation-id })
    operation (len (get approvals operation))
    u0
  )
)

(define-read-only (has-approved (wallet-id uint) (operation-id uint) (user principal))
  (match (map-get? pending-approvals { wallet-id: wallet-id, operation-id: operation-id })
    operation (is-some (index-of (get approvals operation) user))
    false
  )
)

(define-read-only (can-execute-operation (wallet-id uint) (operation-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (match (map-get? pending-approvals { wallet-id: wallet-id, operation-id: operation-id })
        operation 
          (and 
            (get is-multisig wallet)
            (>= (len (get approvals operation)) (get approval-threshold wallet))
            (>= stacks-block-height (get unlock-height wallet))
          )
        false
      )
    false
  )
)

(define-read-only (calculate-vested-amount (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (if (get has-vesting wallet)
        (let (
          (current-height stacks-block-height)
          (vesting-start (get vesting-start wallet))
          (vesting-duration (get vesting-duration wallet))
          (cliff-period (get cliff-period wallet))
          (total-balance (+ (get balance wallet) (get claimed-amount wallet)))
        )
          (if (< current-height (+ vesting-start cliff-period))
            u0
            (if (>= current-height (+ vesting-start vesting-duration))
              total-balance
              (let (
                (elapsed-time (- current-height vesting-start))
                (vesting-progress (/ (* elapsed-time u100) vesting-duration))
              )
                (/ (* total-balance vesting-progress) u100)
              )
            )
          )
        )
        u0
      )
    u0
  )
)

(define-read-only (get-vested-info (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (if (get has-vesting wallet)
        (let (
          (vested-amount (calculate-vested-amount wallet-id))
          (claimed-amount (get claimed-amount wallet))
          (available-amount (- vested-amount claimed-amount))
        )
          (some { 
            vested-amount: vested-amount,
            claimed-amount: claimed-amount,
            available-amount: available-amount,
            vesting-start: (get vesting-start wallet),
            vesting-duration: (get vesting-duration wallet),
            cliff-period: (get cliff-period wallet)
          })
        )
        none
      )
    none
  )
)

(define-read-only (get-vesting-progress (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (if (get has-vesting wallet)
        (let (
          (current-height stacks-block-height)
          (vesting-start (get vesting-start wallet))
          (vesting-duration (get vesting-duration wallet))
        )
          (if (< current-height vesting-start)
            u0
            (if (>= current-height (+ vesting-start vesting-duration))
              u100
              (let (
                (elapsed-time (- current-height vesting-start))
              )
                (/ (* elapsed-time u100) vesting-duration)
              )
            )
          )
        )
        u0
      )
    u0
  )
)

(define-read-only (is-cliff-reached (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (if (get has-vesting wallet)
        (>= stacks-block-height (+ (get vesting-start wallet) (get cliff-period wallet)))
        true
      )
    false
  )
)

(define-read-only (blocks-until-cliff (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (if (get has-vesting wallet)
        (let (
          (cliff-height (+ (get vesting-start wallet) (get cliff-period wallet)))
        )
          (if (>= stacks-block-height cliff-height)
            u0
            (- cliff-height stacks-block-height)
          )
        )
        u0
      )
    u0
  )
)

(define-read-only (blocks-until-fully-vested (wallet-id uint))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet 
      (if (get has-vesting wallet)
        (let (
          (vesting-end (+ (get vesting-start wallet) (get vesting-duration wallet)))
        )
          (if (>= stacks-block-height vesting-end)
            u0
            (- vesting-end stacks-block-height)
          )
        )
        u0
      )
    u0
  )
)

(define-read-only (is-wallet-owner (wallet-id uint) (user principal))
  (match (map-get? wallets { wallet-id: wallet-id })
    wallet (is-eq (get owner wallet) user)
    false
  )
)
