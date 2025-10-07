;; Illegal Logging Incident Tracking Contract
;; Report illegal harvests, seizures, and enforcement outcomes

;; Constants
(define-constant ERR-NOT-AUTHORIZED u400)
(define-constant ERR-INCIDENT-NOT-FOUND u401)
(define-constant ERR-INVALID-STATUS u402)
(define-constant ERR-ALREADY-RESOLVED u403)
(define-constant ERR-INVALID-EVIDENCE u404)
(define-constant ERR-WHISTLEBLOWER-EXISTS u405)

;; Data variables
(define-data-var incident-counter uint u0)
(define-data-var enforcement-counter uint u0)
(define-data-var seizure-counter uint u0)

;; Data maps
(define-map incidents
  { incident-id: uint }
  {
    reporter: principal,
    incident-type: (string-ascii 30),
    location: (string-ascii 256),
    coordinates: { lat: int, lng: int },
    description: (string-ascii 512),
    estimated-volume: uint,
    species-affected: (list 10 (string-ascii 50)),
    evidence-hashes: (list 10 (string-ascii 64)),
    severity-level: uint,
    reported-date: uint,
    status: (string-ascii 20),
    assigned-officer: (optional principal),
    anonymous: bool
  }
)

(define-map enforcement-actions
  { action-id: uint }
  {
    incident-id: uint,
    officer: principal,
    action-type: (string-ascii 30),
    action-date: uint,
    description: (string-ascii 512),
    outcome: (string-ascii 30),
    penalties-imposed: uint,
    follow-up-required: bool,
    follow-up-date: (optional uint)
  }
)

(define-map seizures
  { seizure-id: uint }
  {
    incident-id: uint,
    seizing-authority: principal,
    items-seized: (list 20 (string-ascii 100)),
    estimated-value: uint,
    custody-location: (string-ascii 256),
    seizure-date: uint,
    legal-status: (string-ascii 30),
    disposal-method: (optional (string-ascii 50)),
    disposal-date: (optional uint)
  }
)

(define-map authorized-officers
  { officer: principal }
  {
    authorized: bool,
    badge-number: (string-ascii 20),
    department: (string-ascii 100),
    jurisdiction: (string-ascii 100),
    specialization: (list 5 (string-ascii 30))
  }
)

(define-map whistleblower-protections
  { protection-id: uint }
  {
    reporter: principal,
    incident-id: uint,
    protection-level: (string-ascii 20),
    threat-assessment: uint,
    protection-measures: (list 10 (string-ascii 100)),
    active: bool,
    expiry-date: uint
  }
)

(define-map investigation-updates
  { update-id: uint }
  {
    incident-id: uint,
    investigator: principal,
    update-type: (string-ascii 30),
    findings: (string-ascii 512),
    evidence-collected: (list 10 (string-ascii 64)),
    update-date: uint,
    next-steps: (string-ascii 256)
  }
)

;; Authorization functions
(define-private (is-authorized-officer (officer principal))
  (default-to false (get authorized (map-get? authorized-officers { officer: officer })))
)

(define-private (is-incident-reporter (incident-id uint) (reporter principal))
  (match (map-get? incidents { incident-id: incident-id })
    incident-data
      (or
        (is-eq reporter (get reporter incident-data))
        (get anonymous incident-data)
      )
    false
  )
)

(define-private (calculate-severity-score 
  (volume uint)
  (species-count uint)
  (evidence-count uint)
)
  (let
    (
      (volume-score (if (< (/ volume u1000) u50) (/ volume u1000) u50))
      (species-score (* species-count u5))
      (evidence-score (* evidence-count u3))
    )
    (if (< (+ volume-score species-score evidence-score) u100) (+ volume-score species-score evidence-score) u100)
  )
)

;; Officer management
(define-public (authorize-officer
  (officer principal)
  (badge-number (string-ascii 20))
  (department (string-ascii 100))
  (jurisdiction (string-ascii 100))
  (specialization (list 5 (string-ascii 30)))
)
  (begin
    (asserts! (is-authorized-officer tx-sender) (err ERR-NOT-AUTHORIZED))
    (map-set authorized-officers
      { officer: officer }
      {
        authorized: true,
        badge-number: badge-number,
        department: department,
        jurisdiction: jurisdiction,
        specialization: specialization
      }
    )
    (ok true)
  )
)

;; Incident reporting
(define-public (report-incident
  (incident-type (string-ascii 30))
  (location (string-ascii 256))
  (lat int)
  (lng int)
  (description (string-ascii 512))
  (estimated-volume uint)
  (species-affected (list 10 (string-ascii 50)))
  (evidence-hashes (list 10 (string-ascii 64)))
  (anonymous bool)
)
  (let 
    (
      (incident-id (+ (var-get incident-counter) u1))
      (severity (calculate-severity-score estimated-volume (len species-affected) (len evidence-hashes)))
      (coordinates { lat: lat, lng: lng })
    )
    (asserts! (> (len evidence-hashes) u0) (err ERR-INVALID-EVIDENCE))
    
    (map-set incidents
      { incident-id: incident-id }
      {
        reporter: tx-sender,
        incident-type: incident-type,
        location: location,
        coordinates: coordinates,
        description: description,
        estimated-volume: estimated-volume,
        species-affected: species-affected,
        evidence-hashes: evidence-hashes,
        severity-level: severity,
        reported-date: stacks-block-height,
        status: "reported",
        assigned-officer: none,
        anonymous: anonymous
      }
    )
    
    (var-set incident-counter incident-id)
    (ok incident-id)
  )
)

(define-public (assign-incident
  (incident-id uint)
  (officer principal)
)
  (let ((incident-data (unwrap! (map-get? incidents { incident-id: incident-id }) (err ERR-INCIDENT-NOT-FOUND))))
    (asserts! (is-authorized-officer tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-authorized-officer officer) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-eq (get status incident-data) "reported") (err ERR-INVALID-STATUS))
    
    (map-set incidents
      { incident-id: incident-id }
      (merge incident-data
        {
          assigned-officer: (some officer),
          status: "investigating"
        }
      )
    )
    (ok true)
  )
)

;; Enforcement actions
(define-public (record-enforcement-action
  (incident-id uint)
  (action-type (string-ascii 30))
  (description (string-ascii 512))
  (outcome (string-ascii 30))
  (penalties-imposed uint)
  (follow-up-required bool)
  (follow-up-blocks (optional uint))
)
  (let 
    (
      (action-id (+ (var-get enforcement-counter) u1))
      (incident-data (unwrap! (map-get? incidents { incident-id: incident-id }) (err ERR-INCIDENT-NOT-FOUND)))
      (follow-up-date (if follow-up-required
                        (match follow-up-blocks
                          blocks (some (+ stacks-block-height blocks))
                          (some (+ stacks-block-height u1000))
                        )
                        none
                      ))
    )
    (asserts! (is-authorized-officer tx-sender) (err ERR-NOT-AUTHORIZED))
    
    (map-set enforcement-actions
      { action-id: action-id }
      {
        incident-id: incident-id,
        officer: tx-sender,
        action-type: action-type,
        action-date: stacks-block-height,
        description: description,
        outcome: outcome,
        penalties-imposed: penalties-imposed,
        follow-up-required: follow-up-required,
        follow-up-date: follow-up-date
      }
    )
    
    ;; Update incident status based on outcome
    (if (is-eq outcome "resolved")
      (map-set incidents
        { incident-id: incident-id }
        (merge incident-data { status: "resolved" })
      )
      true
    )
    
    (var-set enforcement-counter action-id)
    (ok action-id)
  )
)

;; Seizure management
(define-public (record-seizure
  (incident-id uint)
  (items-seized (list 20 (string-ascii 100)))
  (estimated-value uint)
  (custody-location (string-ascii 256))
  (legal-status (string-ascii 30))
)
  (let ((seizure-id (+ (var-get seizure-counter) u1)))
    (asserts! (is-authorized-officer tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-some (map-get? incidents { incident-id: incident-id })) (err ERR-INCIDENT-NOT-FOUND))
    
    (map-set seizures
      { seizure-id: seizure-id }
      {
        incident-id: incident-id,
        seizing-authority: tx-sender,
        items-seized: items-seized,
        estimated-value: estimated-value,
        custody-location: custody-location,
        seizure-date: stacks-block-height,
        legal-status: legal-status,
        disposal-method: none,
        disposal-date: none
      }
    )
    
    (var-set seizure-counter seizure-id)
    (ok seizure-id)
  )
)

(define-public (update-seizure-disposal
  (seizure-id uint)
  (disposal-method (string-ascii 50))
)
  (let ((seizure-data (unwrap! (map-get? seizures { seizure-id: seizure-id }) (err ERR-INCIDENT-NOT-FOUND))))
    (asserts! (is-authorized-officer tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-none (get disposal-date seizure-data)) (err ERR-ALREADY-RESOLVED))
    
    (map-set seizures
      { seizure-id: seizure-id }
      (merge seizure-data
        {
          disposal-method: (some disposal-method),
          disposal-date: (some stacks-block-height)
        }
      )
    )
    (ok true)
  )
)

;; Whistleblower protection
(define-public (request-protection
  (incident-id uint)
  (protection-level (string-ascii 20))
  (threat-assessment uint)
  (protection-measures (list 10 (string-ascii 100)))
  (protection-blocks uint)
)
  (let ((protection-id incident-id))
    (asserts! (is-incident-reporter incident-id tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (<= threat-assessment u100) (err ERR-INVALID-STATUS))
    
    (map-set whistleblower-protections
      { protection-id: protection-id }
      {
        reporter: tx-sender,
        incident-id: incident-id,
        protection-level: protection-level,
        threat-assessment: threat-assessment,
        protection-measures: protection-measures,
        active: true,
        expiry-date: (+ stacks-block-height protection-blocks)
      }
    )
    (ok protection-id)
  )
)

;; Read-only functions
(define-read-only (get-incident (incident-id uint))
  (map-get? incidents { incident-id: incident-id })
)

(define-read-only (get-enforcement-action (action-id uint))
  (map-get? enforcement-actions { action-id: action-id })
)

(define-read-only (get-seizure (seizure-id uint))
  (map-get? seizures { seizure-id: seizure-id })
)

(define-read-only (get-officer-status (officer principal))
  (map-get? authorized-officers { officer: officer })
)

(define-read-only (get-protection-status (protection-id uint))
  (map-get? whistleblower-protections { protection-id: protection-id })
)

(define-read-only (get-incident-count)
  (var-get incident-counter)
)

(define-read-only (get-enforcement-count)
  (var-get enforcement-counter)
)

(define-read-only (get-seizure-count)
  (var-get seizure-counter)
)
