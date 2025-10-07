;; FSC Label Verification Contract
;; Consumer verification of FSC/PEFC claims with audit references

;; Constants
(define-constant ERR-NOT-AUTHORIZED u300)
(define-constant ERR-CERTIFICATE-NOT-FOUND u301)
(define-constant ERR-INVALID-CERTIFICATE u302)
(define-constant ERR-CERTIFICATE-EXPIRED u303)
(define-constant ERR-AUDIT-FAILED u304)
(define-constant ERR-LABEL-MISMATCH u305)
(define-constant ERR-ALREADY-VERIFIED u306)

;; Data variables
(define-data-var certificate-counter uint u0)
(define-data-var verification-counter uint u0)
(define-data-var audit-counter uint u0)

;; Data maps
(define-map certificates
  { certificate-id: uint }
  {
    certificate-number: (string-ascii 50),
    certification-body: principal,
    certificate-type: (string-ascii 10),
    holder: principal,
    scope: (string-ascii 256),
    issue-date: uint,
    expiry-date: uint,
    status: (string-ascii 20),
    forest-area-hectares: uint,
    standards-version: (string-ascii 20)
  }
)

(define-map product-labels
  { label-id: uint }
  {
    product-id: (string-ascii 50),
    certificate-id: uint,
    batch-id: uint,
    label-type: (string-ascii 10),
    product-description: (string-ascii 256),
    manufacturer: principal,
    production-date: uint,
    verified: bool,
    verification-date: (optional uint),
    verifier: (optional principal)
  }
)

(define-map certification-bodies
  { body: principal }
  {
    authorized: bool,
    name: (string-ascii 100),
    accreditation-number: (string-ascii 50),
    jurisdiction: (string-ascii 100),
    standards-supported: (list 5 (string-ascii 10))
  }
)

(define-map audit-reports
  { audit-id: uint }
  {
    certificate-id: uint,
    auditor: principal,
    audit-type: (string-ascii 30),
    audit-date: uint,
    findings: (list 20 (string-ascii 100)),
    non-conformities: uint,
    corrective-actions: (list 10 (string-ascii 100)),
    passed: bool,
    next-audit-due: uint
  }
)

(define-map consumer-verifications
  { verification-id: uint }
  {
    label-id: uint,
    consumer: principal,
    verification-method: (string-ascii 30),
    verification-date: uint,
    result: bool,
    confidence-score: uint
  }
)

;; Authorization and validation functions
(define-private (is-authorized-certification-body (body principal))
  (default-to false (get authorized (map-get? certification-bodies { body: body })))
)

(define-private (is-certificate-valid (certificate-id uint))
  (match (map-get? certificates { certificate-id: certificate-id })
    cert-data
      (and
        (< stacks-block-height (get expiry-date cert-data))
        (is-eq (get status cert-data) "active")
      )
    false
  )
)

(define-private (is-valid-certificate-type (cert-type (string-ascii 10)))
  (or
    (is-eq cert-type "FSC")
    (is-eq cert-type "PEFC")
    (is-eq cert-type "SFI")
    (is-eq cert-type "ATFS")
  )
)

(define-private (calculate-confidence-score 
  (certificate-valid bool)
  (audit-passed bool)
  (chain-verified bool)
)
  (let
    (
      (base-score (if certificate-valid u40 u0))
      (audit-score (if audit-passed u30 u0))
      (chain-score (if chain-verified u30 u0))
    )
    (+ base-score audit-score chain-score)
  )
)

;; Certification body management
(define-public (register-certification-body
  (body principal)
  (name (string-ascii 100))
  (accreditation-number (string-ascii 50))
  (jurisdiction (string-ascii 100))
  (standards-supported (list 5 (string-ascii 10)))
)
  (begin
    (asserts! (is-authorized-certification-body tx-sender) (err ERR-NOT-AUTHORIZED))
    (map-set certification-bodies
      { body: body }
      {
        authorized: true,
        name: name,
        accreditation-number: accreditation-number,
        jurisdiction: jurisdiction,
        standards-supported: standards-supported
      }
    )
    (ok true)
  )
)

;; Certificate management
(define-public (issue-certificate
  (certificate-number (string-ascii 50))
  (certificate-type (string-ascii 10))
  (holder principal)
  (scope (string-ascii 256))
  (validity-blocks uint)
  (forest-area-hectares uint)
  (standards-version (string-ascii 20))
)
  (let ((certificate-id (+ (var-get certificate-counter) u1)))
    (asserts! (is-authorized-certification-body tx-sender) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-valid-certificate-type certificate-type) (err ERR-INVALID-CERTIFICATE))
    (asserts! (> validity-blocks u0) (err ERR-INVALID-CERTIFICATE))
    
    (map-set certificates
      { certificate-id: certificate-id }
      {
        certificate-number: certificate-number,
        certification-body: tx-sender,
        certificate-type: certificate-type,
        holder: holder,
        scope: scope,
        issue-date: stacks-block-height,
        expiry-date: (+ stacks-block-height validity-blocks),
        status: "active",
        forest-area-hectares: forest-area-hectares,
        standards-version: standards-version
      }
    )
    (var-set certificate-counter certificate-id)
    (ok certificate-id)
  )
)

(define-public (update-certificate-status
  (certificate-id uint)
  (new-status (string-ascii 20))
)
  (let ((cert-data (unwrap! (map-get? certificates { certificate-id: certificate-id }) (err ERR-CERTIFICATE-NOT-FOUND))))
    (asserts! (is-eq tx-sender (get certification-body cert-data)) (err ERR-NOT-AUTHORIZED))
    (asserts! (or (is-eq new-status "active") (is-eq new-status "suspended") (is-eq new-status "revoked")) (err ERR-INVALID-CERTIFICATE))
    
    (map-set certificates
      { certificate-id: certificate-id }
      (merge cert-data { status: new-status })
    )
    (ok true)
  )
)

;; Product label management
(define-public (create-product-label
  (product-id (string-ascii 50))
  (certificate-id uint)
  (batch-id uint)
  (label-type (string-ascii 10))
  (product-description (string-ascii 256))
)
  (let ((label-id (+ (var-get verification-counter) u500)))
    (asserts! (is-certificate-valid certificate-id) (err ERR-CERTIFICATE-EXPIRED))
    (asserts! (is-valid-certificate-type label-type) (err ERR-INVALID-CERTIFICATE))
    
    (map-set product-labels
      { label-id: label-id }
      {
        product-id: product-id,
        certificate-id: certificate-id,
        batch-id: batch-id,
        label-type: label-type,
        product-description: product-description,
        manufacturer: tx-sender,
        production-date: stacks-block-height,
        verified: false,
        verification-date: none,
        verifier: none
      }
    )
    (ok label-id)
  )
)

;; Audit management
(define-public (submit-audit-report
  (certificate-id uint)
  (audit-type (string-ascii 30))
  (findings (list 20 (string-ascii 100)))
  (non-conformities uint)
  (corrective-actions (list 10 (string-ascii 100)))
  (passed bool)
  (next-audit-blocks uint)
)
  (let 
    (
      (audit-id (+ (var-get audit-counter) u1))
      (cert-data (unwrap! (map-get? certificates { certificate-id: certificate-id }) (err ERR-CERTIFICATE-NOT-FOUND)))
    )
    (asserts! (is-authorized-certification-body tx-sender) (err ERR-NOT-AUTHORIZED))
    
    (map-set audit-reports
      { audit-id: audit-id }
      {
        certificate-id: certificate-id,
        auditor: tx-sender,
        audit-type: audit-type,
        audit-date: stacks-block-height,
        findings: findings,
        non-conformities: non-conformities,
        corrective-actions: corrective-actions,
        passed: passed,
        next-audit-due: (+ stacks-block-height next-audit-blocks)
      }
    )
    
    ;; Update certificate status based on audit result
    (if (not passed)
      (map-set certificates
        { certificate-id: certificate-id }
        (merge cert-data { status: "suspended" })
      )
      true
    )
    
    (var-set audit-counter audit-id)
    (ok audit-id)
  )
)

;; Consumer verification
(define-public (verify-product-label
  (label-id uint)
  (verification-method (string-ascii 30))
)
  (let 
    (
      (verification-id (+ (var-get verification-counter) u1))
      (label-data (unwrap! (map-get? product-labels { label-id: label-id }) (err ERR-CERTIFICATE-NOT-FOUND)))
      (cert-valid (is-certificate-valid (get certificate-id label-data)))
      (confidence (calculate-confidence-score cert-valid true true))
    )
    
    (map-set consumer-verifications
      { verification-id: verification-id }
      {
        label-id: label-id,
        consumer: tx-sender,
        verification-method: verification-method,
        verification-date: stacks-block-height,
        result: cert-valid,
        confidence-score: confidence
      }
    )
    
    ;; Update label verification status
    (if cert-valid
      (map-set product-labels
        { label-id: label-id }
        (merge label-data
          {
            verified: true,
            verification-date: (some stacks-block-height),
            verifier: (some tx-sender)
          }
        )
      )
      true
    )
    
    (var-set verification-counter verification-id)
    (ok { result: cert-valid, confidence-score: confidence })
  )
)

;; Read-only functions
(define-read-only (get-certificate (certificate-id uint))
  (map-get? certificates { certificate-id: certificate-id })
)

(define-read-only (get-product-label (label-id uint))
  (map-get? product-labels { label-id: label-id })
)

(define-read-only (get-audit-report (audit-id uint))
  (map-get? audit-reports { audit-id: audit-id })
)

(define-read-only (get-certification-body (body principal))
  (map-get? certification-bodies { body: body })
)

(define-read-only (verify-certificate-validity (certificate-id uint))
  (is-certificate-valid certificate-id)
)

(define-read-only (get-verification-result (verification-id uint))
  (map-get? consumer-verifications { verification-id: verification-id })
)

(define-read-only (get-certificate-count)
  (var-get certificate-counter)
)

(define-read-only (get-verification-count)
  (var-get verification-counter)
)
