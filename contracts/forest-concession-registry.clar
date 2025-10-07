;; Forest Concession Registry Contract
;; Register concessions, harvest plans, and environmental protections

;; Constants
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-CONCESSION-NOT-FOUND u101)
(define-constant ERR-INVALID-STATUS u102)
(define-constant ERR-PLAN-ALREADY-EXISTS u103)
(define-constant ERR-INVALID-COORDINATES u104)
(define-constant ERR-CONCESSION-EXPIRED u105)

;; Data variables
(define-data-var concession-counter uint u0)
(define-data-var harvest-plan-counter uint u0)

;; Data maps
(define-map concessions
  { concession-id: uint }
  {
    owner: principal,
    location: (string-ascii 256),
    area-hectares: uint,
    coordinates: { lat: int, lng: int, bounds: (list 10 { lat: int, lng: int }) },
    certification-type: (string-ascii 20),
    expiry-block: uint,
    status: (string-ascii 20),
    registered-block: uint,
    authority: principal
  }
)

(define-map harvest-plans
  { plan-id: uint }
  {
    concession-id: uint,
    planned-volume: uint,
    species: (list 20 (string-ascii 50)),
    harvest-start-block: uint,
    harvest-end-block: uint,
    environmental-measures: (string-ascii 512),
    approved: bool,
    approver: (optional principal),
    submitted-block: uint
  }
)

(define-map concession-authorities
  { authority: principal }
  { authorized: bool, jurisdiction: (string-ascii 100) }
)

(define-map environmental-protections
  { protection-id: uint }
  {
    concession-id: uint,
    protection-type: (string-ascii 50),
    area-hectares: uint,
    coordinates: { lat: int, lng: int, radius: uint },
    description: (string-ascii 256),
    mandatory: bool
  }
)

;; Authorization functions
(define-private (is-authorized-authority (authority principal))
  (default-to false (get authorized (map-get? concession-authorities { authority: authority })))
)

(define-private (is-concession-owner (concession-id uint) (caller principal))
  (match (map-get? concessions { concession-id: concession-id })
    concession-data (is-eq caller (get owner concession-data))
    false
  )
)

(define-private (is-concession-valid (concession-id uint))
  (match (map-get? concessions { concession-id: concession-id })
    concession-data 
      (and 
        (< stacks-block-height (get expiry-block concession-data))
        (is-eq (get status concession-data) "active")
      )
    false
  )
)

;; Validation functions
(define-private (is-valid-coordinates (lat int) (lng int))
  (and 
    (>= lat -90000000) (<= lat 90000000)
    (>= lng -180000000) (<= lng 180000000)
  )
)

(define-private (is-valid-certification-type (cert-type (string-ascii 20)))
  (or 
    (is-eq cert-type "FSC")
    (is-eq cert-type "PEFC")
    (is-eq cert-type "SFI")
    (is-eq cert-type "NONE")
  )
)

;; Authority management functions
(define-public (add-authority (authority principal) (jurisdiction (string-ascii 100)))
  (begin
    (asserts! (is-authorized-authority tx-sender) (err ERR-NOT-AUTHORIZED))
    (map-set concession-authorities
      { authority: authority }
      { authorized: true, jurisdiction: jurisdiction }
    )
    (ok true)
  )
)

(define-public (revoke-authority (authority principal))
  (begin
    (asserts! (is-authorized-authority tx-sender) (err ERR-NOT-AUTHORIZED))
    (map-set concession-authorities
      { authority: authority }
      { authorized: false, jurisdiction: "" }
    )
    (ok true)
  )
)

;; Concession registration functions
(define-public (register-concession 
  (owner principal)
  (location (string-ascii 256))
  (area-hectares uint)
  (lat int)
  (lng int)
  (bounds (list 10 { lat: int, lng: int }))
  (certification-type (string-ascii 20))
  (validity-blocks uint)
)
  (let 
    (
      (concession-id (+ (var-get concession-counter) u1))
      (coordinates { lat: lat, lng: lng, bounds: bounds })
    )
    (asserts! (is-authorized-authority tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-valid-coordinates lat lng) (err ERR-INVALID-COORDINATES))
    (asserts! (is-valid-certification-type certification-type) (err ERR-INVALID-STATUS))
    (asserts! (> validity-blocks u0) (err ERR-INVALID-STATUS))
    
    (map-set concessions
      { concession-id: concession-id }
      {
        owner: owner,
        location: location,
        area-hectares: area-hectares,
        coordinates: coordinates,
        certification-type: certification-type,
        expiry-block: (+ stacks-block-height validity-blocks),
        status: "active",
        registered-block: stacks-block-height,
        authority: tx-sender
      }
    )
    (var-set concession-counter concession-id)
    (ok concession-id)
  )
)

(define-public (update-concession-status (concession-id uint) (new-status (string-ascii 20)))
  (let ((concession-data (unwrap! (map-get? concessions { concession-id: concession-id }) (err ERR-CONCESSION-NOT-FOUND))))
    (asserts! (is-authorized-authority tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (or (is-eq new-status "active") (is-eq new-status "suspended") (is-eq new-status "revoked")) (err ERR-INVALID-STATUS))
    
    (map-set concessions
      { concession-id: concession-id }
      (merge concession-data { status: new-status })
    )
    (ok true)
  )
)

;; Harvest plan functions
(define-public (submit-harvest-plan
  (concession-id uint)
  (planned-volume uint)
  (species (list 20 (string-ascii 50)))
  (harvest-start-block uint)
  (harvest-end-block uint)
  (environmental-measures (string-ascii 512))
)
  (let ((plan-id (+ (var-get harvest-plan-counter) u1)))
    (asserts! (is-concession-valid concession-id) (err ERR-CONCESSION-NOT-FOUND))
    (asserts! (is-concession-owner concession-id tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (> harvest-end-block harvest-start-block) (err ERR-INVALID-STATUS))
    (asserts! (> planned-volume u0) (err ERR-INVALID-STATUS))
    
    (map-set harvest-plans
      { plan-id: plan-id }
      {
        concession-id: concession-id,
        planned-volume: planned-volume,
        species: species,
        harvest-start-block: harvest-start-block,
        harvest-end-block: harvest-end-block,
        environmental-measures: environmental-measures,
        approved: false,
        approver: none,
        submitted-block: stacks-block-height
      }
    )
    (var-set harvest-plan-counter plan-id)
    (ok plan-id)
  )
)

(define-public (approve-harvest-plan (plan-id uint))
  (let ((plan-data (unwrap! (map-get? harvest-plans { plan-id: plan-id }) (err ERR-CONCESSION-NOT-FOUND))))
    (asserts! (is-authorized-authority tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (get approved plan-data)) (err ERR-INVALID-STATUS))
    
    (map-set harvest-plans
      { plan-id: plan-id }
      (merge plan-data { approved: true, approver: (some tx-sender) })
    )
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-concession (concession-id uint))
  (map-get? concessions { concession-id: concession-id })
)

(define-read-only (get-harvest-plan (plan-id uint))
  (map-get? harvest-plans { plan-id: plan-id })
)

(define-read-only (is-concession-active (concession-id uint))
  (is-concession-valid concession-id)
)

(define-read-only (get-authority-status (authority principal))
  (map-get? concession-authorities { authority: authority })
)

(define-read-only (get-concession-count)
  (var-get concession-counter)
)

(define-read-only (get-harvest-plan-count)
  (var-get harvest-plan-counter)
)
