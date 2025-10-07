;; Chain of Custody Timber Tracking Contract
;; Trace logs and lumber through mills and distributors with batch IDs

;; Constants
(define-constant ERR-NOT-AUTHORIZED u200)
(define-constant ERR-BATCH-NOT-FOUND u201)
(define-constant ERR-INVALID-TRANSFER u202)
(define-constant ERR-ALREADY-PROCESSED u203)
(define-constant ERR-INVALID-QUANTITY u204)
(define-constant ERR-CUSTODY-CHAIN-BROKEN u205)
(define-constant ERR-EXPIRED-BATCH u206)

;; Data variables
(define-data-var batch-counter uint u0)
(define-data-var transfer-counter uint u0)

;; Data maps
(define-map timber-batches
  { batch-id: uint }
  {
    origin-concession-id: uint,
    species: (string-ascii 50),
    volume-cubic-meters: uint,
    harvest-date: uint,
    location-coordinates: { lat: int, lng: int },
    certification-numbers: (list 5 (string-ascii 50)),
    current-holder: principal,
    processing-stage: (string-ascii 30),
    quality-grade: (string-ascii 10),
    created-block: uint,
    last-updated: uint
  }
)

(define-map custody-transfers
  { transfer-id: uint }
  {
    batch-id: uint,
    from-holder: principal,
    to-holder: principal,
    transfer-type: (string-ascii 30),
    quantity-transferred: uint,
    location: (string-ascii 256),
    transport-method: (string-ascii 50),
    documents: (list 10 (string-ascii 100)),
    transfer-block: uint,
    verified: bool,
    verifier: (optional principal)
  }
)

(define-map processing-records
  { record-id: uint }
  {
    batch-id: uint,
    processor: principal,
    processing-type: (string-ascii 50),
    input-volume: uint,
    output-volume: uint,
    waste-percentage: uint,
    equipment-used: (string-ascii 100),
    quality-checks: (list 5 (string-ascii 100)),
    processing-date: uint,
    location: (string-ascii 256)
  }
)

(define-map authorized-entities
  { entity: principal }
  {
    authorized: bool,
    entity-type: (string-ascii 30),
    license-number: (string-ascii 50),
    jurisdiction: (string-ascii 100)
  }
)

(define-map quality-inspections
  { inspection-id: uint }
  {
    batch-id: uint,
    inspector: principal,
    inspection-type: (string-ascii 50),
    grade-assigned: (string-ascii 10),
    moisture-content: uint,
    defects-found: (list 10 (string-ascii 50)),
    passed: bool,
    inspection-date: uint,
    notes: (string-ascii 512)
  }
)

;; Authorization functions
(define-private (is-authorized-entity (entity principal))
  (default-to false (get authorized (map-get? authorized-entities { entity: entity })))
)

(define-private (is-batch-holder (batch-id uint) (holder principal))
  (match (map-get? timber-batches { batch-id: batch-id })
    batch-data (is-eq holder (get current-holder batch-data))
    false
  )
)

(define-private (is-valid-processing-stage (stage (string-ascii 30)))
  (or 
    (is-eq stage "raw-log")
    (is-eq stage "rough-lumber")
    (is-eq stage "kiln-dried")
    (is-eq stage "finished-lumber")
    (is-eq stage "manufactured-product")
  )
)

(define-private (calculate-waste-percentage (input uint) (output uint))
  (if (is-eq input u0)
    u0
    (/ (* (- input output) u100) input)
  )
)

;; Entity management functions
(define-public (register-entity 
  (entity principal)
  (entity-type (string-ascii 30))
  (license-number (string-ascii 50))
  (jurisdiction (string-ascii 100))
)
  (begin
    (asserts! (is-authorized-entity tx-sender) (err ERR-NOT-AUTHORIZED))
    (map-set authorized-entities
      { entity: entity }
      {
        authorized: true,
        entity-type: entity-type,
        license-number: license-number,
        jurisdiction: jurisdiction
      }
    )
    (ok true)
  )
)

;; Batch creation and management
(define-public (create-timber-batch
  (origin-concession-id uint)
  (species (string-ascii 50))
  (volume-cubic-meters uint)
  (harvest-date uint)
  (lat int)
  (lng int)
  (certification-numbers (list 5 (string-ascii 50)))
  (quality-grade (string-ascii 10))
)
  (let ((batch-id (+ (var-get batch-counter) u1)))
    (asserts! (is-authorized-entity tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (> volume-cubic-meters u0) (err ERR-INVALID-QUANTITY))
    
    (map-set timber-batches
      { batch-id: batch-id }
      {
        origin-concession-id: origin-concession-id,
        species: species,
        volume-cubic-meters: volume-cubic-meters,
        harvest-date: harvest-date,
        location-coordinates: { lat: lat, lng: lng },
        certification-numbers: certification-numbers,
        current-holder: tx-sender,
        processing-stage: "raw-log",
        quality-grade: quality-grade,
        created-block: stacks-block-height,
        last-updated: stacks-block-height
      }
    )
    (var-set batch-counter batch-id)
    (ok batch-id)
  )
)

(define-public (transfer-custody
  (batch-id uint)
  (to-holder principal)
  (transfer-type (string-ascii 30))
  (quantity-transferred uint)
  (location (string-ascii 256))
  (transport-method (string-ascii 50))
  (documents (list 10 (string-ascii 100)))
)
  (let 
    (
      (transfer-id (+ (var-get transfer-counter) u1))
      (batch-data (unwrap! (map-get? timber-batches { batch-id: batch-id }) (err ERR-BATCH-NOT-FOUND)))
    )
    (asserts! (is-batch-holder batch-id tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-authorized-entity to-holder) (err ERR-NOT-AUTHORIZED))
    (asserts! (> quantity-transferred u0) (err ERR-INVALID-QUANTITY))
    (asserts! (<= quantity-transferred (get volume-cubic-meters batch-data)) (err ERR-INVALID-QUANTITY))
    
    ;; Record the transfer
    (map-set custody-transfers
      { transfer-id: transfer-id }
      {
        batch-id: batch-id,
        from-holder: tx-sender,
        to-holder: to-holder,
        transfer-type: transfer-type,
        quantity-transferred: quantity-transferred,
        location: location,
        transport-method: transport-method,
        documents: documents,
        transfer-block: stacks-block-height,
        verified: false,
        verifier: none
      }
    )
    
    ;; Update batch holder
    (map-set timber-batches
      { batch-id: batch-id }
      (merge batch-data 
        { 
          current-holder: to-holder,
          last-updated: stacks-block-height
        }
      )
    )
    (var-set transfer-counter transfer-id)
    (ok transfer-id)
  )
)

(define-public (verify-transfer (transfer-id uint))
  (let ((transfer-data (unwrap! (map-get? custody-transfers { transfer-id: transfer-id }) (err ERR-BATCH-NOT-FOUND))))
    (asserts! (is-authorized-entity tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (get verified transfer-data)) (err ERR-ALREADY-PROCESSED))
    
    (map-set custody-transfers
      { transfer-id: transfer-id }
      (merge transfer-data 
        {
          verified: true,
          verifier: (some tx-sender)
        }
      )
    )
    (ok true)
  )
)

(define-public (process-batch
  (batch-id uint)
  (processing-type (string-ascii 50))
  (new-stage (string-ascii 30))
  (output-volume uint)
  (equipment-used (string-ascii 100))
  (quality-checks (list 5 (string-ascii 100)))
  (location (string-ascii 256))
)
  (let 
    (
      (batch-data (unwrap! (map-get? timber-batches { batch-id: batch-id }) (err ERR-BATCH-NOT-FOUND)))
      (input-volume (get volume-cubic-meters batch-data))
      (waste-percentage (calculate-waste-percentage input-volume output-volume))
      (record-id (+ (var-get batch-counter) u1000))
    )
    (asserts! (is-batch-holder batch-id tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-valid-processing-stage new-stage) (err ERR-INVALID-TRANSFER))
    (asserts! (<= output-volume input-volume) (err ERR-INVALID-QUANTITY))
    
    ;; Record processing details
    (map-set processing-records
      { record-id: record-id }
      {
        batch-id: batch-id,
        processor: tx-sender,
        processing-type: processing-type,
        input-volume: input-volume,
        output-volume: output-volume,
        waste-percentage: waste-percentage,
        equipment-used: equipment-used,
        quality-checks: quality-checks,
        processing-date: stacks-block-height,
        location: location
      }
    )
    
    ;; Update batch with new stage and volume
    (map-set timber-batches
      { batch-id: batch-id }
      (merge batch-data
        {
          processing-stage: new-stage,
          volume-cubic-meters: output-volume,
          last-updated: stacks-block-height
        }
      )
    )
    (ok record-id)
  )
)

;; Read-only functions
(define-read-only (get-timber-batch (batch-id uint))
  (map-get? timber-batches { batch-id: batch-id })
)

(define-read-only (get-custody-transfer (transfer-id uint))
  (map-get? custody-transfers { transfer-id: transfer-id })
)

(define-read-only (get-processing-record (record-id uint))
  (map-get? processing-records { record-id: record-id })
)

(define-read-only (get-entity-status (entity principal))
  (map-get? authorized-entities { entity: entity })
)

(define-read-only (get-batch-count)
  (var-get batch-counter)
)

(define-read-only (get-transfer-count)
  (var-get transfer-counter)
)

(define-read-only (verify-custody-chain (batch-id uint))
  (is-some (map-get? timber-batches { batch-id: batch-id }))
)
