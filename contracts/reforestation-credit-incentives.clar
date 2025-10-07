;; Reforestation Credit Incentives Contract
;; Token credits for verified reforestation and biodiversity actions

;; Constants
(define-constant ERR-NOT-AUTHORIZED u500)
(define-constant ERR-PROJECT-NOT-FOUND u501)
(define-constant ERR-INSUFFICIENT-CREDITS u502)
(define-constant ERR-INVALID-VERIFICATION u503)
(define-constant ERR-PROJECT-COMPLETED u504)
(define-constant ERR-CREDIT-EXPIRED u505)
(define-constant ERR-INVALID-TRADE u506)

;; Credit token constants
(define-constant TOKEN-NAME "Reforestation Credit Token")
(define-constant TOKEN-SYMBOL "RCT")
(define-constant TOKEN-DECIMALS u6)
(define-constant CREDITS-PER-HECTARE u1000000)
(define-constant BIODIVERSITY-MULTIPLIER u150)
(define-constant CARBON-MULTIPLIER u200)

;; Data variables
(define-data-var project-counter uint u0)
(define-data-var verification-counter uint u0)
(define-data-var trade-counter uint u0)
(define-data-var total-credits-issued uint u0)

;; Data maps
(define-map reforestation-projects
  { project-id: uint }
  {
    owner: principal,
    location: (string-ascii 256),
    coordinates: { lat: int, lng: int, area: uint },
    project-type: (string-ascii 30),
    planned-area-hectares: uint,
    planted-area-hectares: uint,
    tree-species: (list 20 (string-ascii 50)),
    planting-start-date: uint,
    target-completion-date: uint,
    status: (string-ascii 20),
    carbon-sequestration-estimate: uint,
    biodiversity-score: uint,
    credits-earned: uint,
    verified: bool,
    last-verification-date: (optional uint)
  }
)

(define-map credit-balances
  { holder: principal }
  { balance: uint }
)

(define-map verification-reports
  { verification-id: uint }
  {
    project-id: uint,
    verifier: principal,
    verification-type: (string-ascii 30),
    area-verified: uint,
    survival-rate: uint,
    carbon-measurement: uint,
    biodiversity-assessment: uint,
    credits-awarded: uint,
    verification-date: uint,
    next-verification-due: uint,
    passed: bool,
    notes: (string-ascii 512)
  }
)

(define-map authorized-verifiers
  { verifier: principal }
  {
    authorized: bool,
    certification: (string-ascii 100),
    specialization: (list 5 (string-ascii 30)),
    reputation-score: uint
  }
)

(define-map credit-trades
  { trade-id: uint }
  {
    seller: principal,
    buyer: principal,
    credits-amount: uint,
    price-per-credit: uint,
    trade-date: uint,
    status: (string-ascii 20),
    project-source: uint,
    expiry-date: uint
  }
)

(define-map carbon-offset-registry
  { offset-id: uint }
  {
    project-id: uint,
    credits-retired: uint,
    retirement-date: uint,
    retired-by: principal,
    retirement-purpose: (string-ascii 100),
    co2-equivalent: uint
  }
)

;; Authorization functions
(define-private (is-authorized-verifier (verifier principal))
  (default-to false (get authorized (map-get? authorized-verifiers { verifier: verifier })))
)

(define-private (is-project-owner (project-id uint) (owner principal))
  (match (map-get? reforestation-projects { project-id: project-id })
    project-data (is-eq owner (get owner project-data))
    false
  )
)

;; Credit calculation functions
(define-private (calculate-base-credits (area-hectares uint))
  (* area-hectares CREDITS-PER-HECTARE)
)

(define-private (calculate-biodiversity-bonus 
  (base-credits uint)
  (biodiversity-score uint)
)
  (if (> biodiversity-score u70)
    (/ (* base-credits (- BIODIVERSITY-MULTIPLIER u100)) u100)
    u0
  )
)

(define-private (calculate-carbon-bonus 
  (base-credits uint)
  (carbon-sequestration uint)
)
  (if (> carbon-sequestration u50)
    (/ (* base-credits (- CARBON-MULTIPLIER u100)) u100)
    u0
  )
)

(define-private (get-credit-balance (holder principal))
  (default-to u0 (get balance (map-get? credit-balances { holder: holder })))
)

;; Verifier management
(define-public (authorize-verifier
  (verifier principal)
  (certification (string-ascii 100))
  (specialization (list 5 (string-ascii 30)))
)
  (begin
    (asserts! (is-authorized-verifier tx-sender) (err ERR-NOT-AUTHORIZED))
    (map-set authorized-verifiers
      { verifier: verifier }
      {
        authorized: true,
        certification: certification,
        specialization: specialization,
        reputation-score: u100
      }
    )
    (ok true)
  )
)

;; Project management
(define-public (register-project
  (location (string-ascii 256))
  (lat int)
  (lng int)
  (area uint)
  (project-type (string-ascii 30))
  (planned-area-hectares uint)
  (tree-species (list 20 (string-ascii 50)))
  (target-completion-blocks uint)
  (carbon-estimate uint)
)
  (let 
    (
      (project-id (+ (var-get project-counter) u1))
      (coordinates { lat: lat, lng: lng, area: area })
    )
    (asserts! (> planned-area-hectares u0) (err ERR-INVALID-VERIFICATION))
    
    (map-set reforestation-projects
      { project-id: project-id }
      {
        owner: tx-sender,
        location: location,
        coordinates: coordinates,
        project-type: project-type,
        planned-area-hectares: planned-area-hectares,
        planted-area-hectares: u0,
        tree-species: tree-species,
        planting-start-date: stacks-block-height,
        target-completion-date: (+ stacks-block-height target-completion-blocks),
        status: "planning",
        carbon-sequestration-estimate: carbon-estimate,
        biodiversity-score: u0,
        credits-earned: u0,
        verified: false,
        last-verification-date: none
      }
    )
    
    (var-set project-counter project-id)
    (ok project-id)
  )
)

(define-public (update-project-progress
  (project-id uint)
  (planted-area-hectares uint)
  (new-status (string-ascii 20))
)
  (let ((project-data (unwrap! (map-get? reforestation-projects { project-id: project-id }) (err ERR-PROJECT-NOT-FOUND))))
    (asserts! (is-project-owner project-id tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (<= planted-area-hectares (get planned-area-hectares project-data)) (err ERR-INVALID-VERIFICATION))
    
    (map-set reforestation-projects
      { project-id: project-id }
      (merge project-data
        {
          planted-area-hectares: planted-area-hectares,
          status: new-status
        }
      )
    )
    (ok true)
  )
)

;; Verification and credit issuance
(define-public (submit-verification
  (project-id uint)
  (verification-type (string-ascii 30))
  (area-verified uint)
  (survival-rate uint)
  (carbon-measurement uint)
  (biodiversity-assessment uint)
  (next-verification-blocks uint)
  (notes (string-ascii 512))
)
  (let 
    (
      (verification-id (+ (var-get verification-counter) u1))
      (project-data (unwrap! (map-get? reforestation-projects { project-id: project-id }) (err ERR-PROJECT-NOT-FOUND)))
      (base-credits (calculate-base-credits area-verified))
      (biodiversity-bonus (calculate-biodiversity-bonus base-credits biodiversity-assessment))
      (carbon-bonus (calculate-carbon-bonus base-credits carbon-measurement))
      (total-credits (+ base-credits biodiversity-bonus carbon-bonus))
      (passed (and (>= survival-rate u70) (> area-verified u0)))
    )
    (asserts! (is-authorized-verifier tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (<= area-verified (get planted-area-hectares project-data)) (err ERR-INVALID-VERIFICATION))
    
    (map-set verification-reports
      { verification-id: verification-id }
      {
        project-id: project-id,
        verifier: tx-sender,
        verification-type: verification-type,
        area-verified: area-verified,
        survival-rate: survival-rate,
        carbon-measurement: carbon-measurement,
        biodiversity-assessment: biodiversity-assessment,
        credits-awarded: (if passed total-credits u0),
        verification-date: stacks-block-height,
        next-verification-due: (+ stacks-block-height next-verification-blocks),
        passed: passed,
        notes: notes
      }
    )
    
    ;; Issue credits if verification passed
    (if passed
      (begin
        ;; Update project
        (map-set reforestation-projects
          { project-id: project-id }
          (merge project-data
            {
              biodiversity-score: biodiversity-assessment,
              credits-earned: (+ (get credits-earned project-data) total-credits),
              verified: true,
              last-verification-date: (some stacks-block-height)
            }
          )
        )
        ;; Issue credits to project owner
        (let ((owner (get owner project-data)))
          (map-set credit-balances
            { holder: owner }
            { balance: (+ (get-credit-balance owner) total-credits) }
          )
        )
        (var-set total-credits-issued (+ (var-get total-credits-issued) total-credits))
      )
      true
    )
    
    (var-set verification-counter verification-id)
    (ok verification-id)
  )
)

;; Credit trading functions
(define-public (create-credit-trade
  (buyer principal)
  (credits-amount uint)
  (price-per-credit uint)
  (project-source uint)
  (expiry-blocks uint)
)
  (let ((trade-id (+ (var-get trade-counter) u1)))
    (asserts! (>= (get-credit-balance tx-sender) credits-amount) (err ERR-INSUFFICIENT-CREDITS))
    (asserts! (> credits-amount u0) (err ERR-INVALID-TRADE))
    (asserts! (is-some (map-get? reforestation-projects { project-id: project-source })) (err ERR-PROJECT-NOT-FOUND))
    
    (map-set credit-trades
      { trade-id: trade-id }
      {
        seller: tx-sender,
        buyer: buyer,
        credits-amount: credits-amount,
        price-per-credit: price-per-credit,
        trade-date: stacks-block-height,
        status: "pending",
        project-source: project-source,
        expiry-date: (+ stacks-block-height expiry-blocks)
      }
    )
    
    (var-set trade-counter trade-id)
    (ok trade-id)
  )
)

(define-public (execute-credit-trade (trade-id uint))
  (let ((trade-data (unwrap! (map-get? credit-trades { trade-id: trade-id }) (err ERR-INVALID-TRADE))))
    (asserts! (is-eq tx-sender (get buyer trade-data)) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-eq (get status trade-data) "pending") (err ERR-INVALID-TRADE))
    (asserts! (< stacks-block-height (get expiry-date trade-data)) (err ERR-CREDIT-EXPIRED))
    
    (let 
      (
        (seller (get seller trade-data))
        (buyer (get buyer trade-data))
        (credits (get credits-amount trade-data))
      )
      ;; Transfer credits
      (map-set credit-balances
        { holder: seller }
        { balance: (- (get-credit-balance seller) credits) }
      )
      (map-set credit-balances
        { holder: buyer }
        { balance: (+ (get-credit-balance buyer) credits) }
      )
      ;; Update trade status
      (map-set credit-trades
        { trade-id: trade-id }
        (merge trade-data { status: "completed" })
      )
    )
    (ok true)
  )
)

;; Carbon offset retirement
(define-public (retire-credits-for-offset
  (credits-amount uint)
  (project-source uint)
  (retirement-purpose (string-ascii 100))
)
  (let ((offset-id (+ (var-get verification-counter) u1000)))
    (asserts! (>= (get-credit-balance tx-sender) credits-amount) (err ERR-INSUFFICIENT-CREDITS))
    (asserts! (is-some (map-get? reforestation-projects { project-id: project-source })) (err ERR-PROJECT-NOT-FOUND))
    
    ;; Retire credits
    (map-set credit-balances
      { holder: tx-sender }
      { balance: (- (get-credit-balance tx-sender) credits-amount) }
    )
    
    ;; Record retirement
    (map-set carbon-offset-registry
      { offset-id: offset-id }
      {
        project-id: project-source,
        credits-retired: credits-amount,
        retirement-date: stacks-block-height,
        retired-by: tx-sender,
        retirement-purpose: retirement-purpose,
        co2-equivalent: (/ credits-amount u1000)
      }
    )
    
    (ok offset-id)
  )
)

;; Read-only functions
(define-read-only (get-project (project-id uint))
  (map-get? reforestation-projects { project-id: project-id })
)

(define-read-only (get-credit-balance-of (holder principal))
  (get-credit-balance holder)
)

(define-read-only (get-verification-report (verification-id uint))
  (map-get? verification-reports { verification-id: verification-id })
)

(define-read-only (get-trade (trade-id uint))
  (map-get? credit-trades { trade-id: trade-id })
)

(define-read-only (get-verifier-status (verifier principal))
  (map-get? authorized-verifiers { verifier: verifier })
)

(define-read-only (get-offset-record (offset-id uint))
  (map-get? carbon-offset-registry { offset-id: offset-id })
)

(define-read-only (get-total-credits-issued)
  (var-get total-credits-issued)
)

(define-read-only (get-project-count)
  (var-get project-counter)
)

(define-read-only (get-token-info)
  {
    name: TOKEN-NAME,
    symbol: TOKEN-SYMBOL,
    decimals: TOKEN-DECIMALS,
    total-supply: (var-get total-credits-issued)
  }
)
