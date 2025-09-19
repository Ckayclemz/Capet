;; Research Patent Licensing Contract
;; Enables licensing fee distribution for research patents

;; Error constants
(define-constant ERR-ACCESS-FORBIDDEN (err u100))
(define-constant ERR-PATENT-NOT-REGISTERED (err u101))
(define-constant ERR-INVALID-PARAMETERS (err u102))
(define-constant ERR-ALREADY-FILED (err u103))
(define-constant ERR-FUNDING-INSUFFICIENT (err u104))
(define-constant ERR-NO-LICENSE-FEES (err u105))

;; Constants
(define-constant MAX-LICENSING-RATE u450) ;; 45%
(define-constant CONTRIBUTION-SCALE u1000) ;; 100% = 1000
(define-constant CONTRACT-OWNER tx-sender)

;; Data structures
(define-map patents
  { patent-id: uint }
  {
    patent-title: (string-utf8 128),
    lead-researcher: principal,
    licensing-fee: uint,
    licensing-rate: uint,
    filed: bool,
    active: bool
  }
)

(define-map researchers
  { patent-id: uint, researcher: principal }
  { contribution-percentage: uint, department: (string-ascii 32) }
)

(define-map license-fees
  { patent-id: uint, researcher: principal }
  { accumulated-fees: uint }
)

(define-data-var next-patent-id uint u1)

;; Register new research patent
(define-public (register-patent 
                (patent-title (string-utf8 128))
                (licensing-fee uint)
                (licensing-rate uint))
  (let ((patent-id (var-get next-patent-id)))
    ;; Validate inputs
    (asserts! (> licensing-fee u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= licensing-rate MAX-LICENSING-RATE) ERR-INVALID-PARAMETERS)
    (asserts! (> (len patent-title) u0) ERR-INVALID-PARAMETERS)
    
    ;; Create patent record
    (map-set patents
      { patent-id: patent-id }
      {
        patent-title: patent-title,
        lead-researcher: tx-sender,
        licensing-fee: licensing-fee,
        licensing-rate: licensing-rate,
        filed: false,
        active: true
      })
    
    ;; Add lead researcher as primary contributor
    (map-set researchers
      { patent-id: patent-id, researcher: tx-sender }
      { contribution-percentage: CONTRIBUTION-SCALE, department: "lead-research" })
    
    ;; Increment counter
    (var-set next-patent-id (+ patent-id u1))
    (ok patent-id)))

;; Add research contributor to patent
(define-public (add-researcher
                (patent-id uint)
                (researcher principal)
                (contribution-percentage uint)
                (department (string-ascii 32)))
  (let ((patent (unwrap! (map-get? patents { patent-id: patent-id }) ERR-PATENT-NOT-REGISTERED))
        (lead-data (unwrap! (map-get? researchers { patent-id: patent-id, researcher: (get lead-researcher patent) }) ERR-PATENT-NOT-REGISTERED))
        (updated-lead-contribution (- (get contribution-percentage lead-data) contribution-percentage)))
    
    ;; Validate inputs
    (asserts! (< patent-id (var-get next-patent-id)) ERR-PATENT-NOT-REGISTERED)
    (asserts! (is-eq tx-sender (get lead-researcher patent)) ERR-ACCESS-FORBIDDEN)
    (asserts! (not (get filed patent)) ERR-ALREADY-FILED)
    (asserts! (> contribution-percentage u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= contribution-percentage CONTRIBUTION-SCALE) ERR-INVALID-PARAMETERS)
    (asserts! (<= contribution-percentage (get contribution-percentage lead-data)) ERR-INVALID-PARAMETERS)
    (asserts! (> (len department) u0) ERR-INVALID-PARAMETERS)
    (asserts! (not (is-eq researcher (get lead-researcher patent))) ERR-INVALID-PARAMETERS)
    
    ;; Add researcher
    (map-set researchers
      { patent-id: patent-id, researcher: researcher }
      { contribution-percentage: contribution-percentage, department: department })
    
    ;; Update lead researcher's contribution
    (map-set researchers
      { patent-id: patent-id, researcher: (get lead-researcher patent) }
      { contribution-percentage: updated-lead-contribution, department: "lead-research" })
    
    (ok true)))

;; File patent application
(define-public (file-patent-application (patent-id uint))
  (begin
    ;; Validate patent-id bounds first
    (asserts! (< patent-id (var-get next-patent-id)) ERR-PATENT-NOT-REGISTERED)
    (asserts! (> patent-id u0) ERR-INVALID-PARAMETERS)
    
    (let ((patent (unwrap! (map-get? patents { patent-id: patent-id }) ERR-PATENT-NOT-REGISTERED))
          (fee (get licensing-fee patent))
          (lead-researcher (get lead-researcher patent)))
      
      ;; Validate other inputs
      (asserts! (is-eq tx-sender lead-researcher) ERR-ACCESS-FORBIDDEN)
      (asserts! (get active patent) ERR-INVALID-PARAMETERS)
      (asserts! (not (get filed patent)) ERR-ALREADY-FILED)
      (asserts! (>= (stx-get-balance tx-sender) fee) ERR-FUNDING-INSUFFICIENT)
      
      ;; Transfer filing fee to contract
      (try! (stx-transfer? fee tx-sender (as-contract tx-sender)))
      
      ;; Mark as filed
      (map-set patents
        { patent-id: patent-id }
        (merge patent { filed: true }))
      
      (ok true))))

;; Process patent licensing transaction
(define-public (process-patent-licensing
                (patent-id uint)
                (licensee principal)
                (licensing-payment uint))
  (begin
    ;; Validate inputs first
    (asserts! (< patent-id (var-get next-patent-id)) ERR-PATENT-NOT-REGISTERED)
    (asserts! (> patent-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (> licensing-payment u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= licensing-payment u1000000000) ERR-INVALID-PARAMETERS)
    
    (let ((patent (unwrap! (map-get? patents { patent-id: patent-id }) ERR-PATENT-NOT-REGISTERED))
          (institution-cut (/ (* licensing-payment (get licensing-rate patent)) CONTRIBUTION-SCALE))
          (researcher-cut (- licensing-payment institution-cut)))
      
      ;; Validate patent state
      (asserts! (get active patent) ERR-INVALID-PARAMETERS)
      (asserts! (get filed patent) ERR-INVALID-PARAMETERS)
      (asserts! (>= (stx-get-balance tx-sender) licensing-payment) ERR-FUNDING-INSUFFICIENT)
      
      ;; Transfer licensing payment to contract
      (try! (stx-transfer? licensing-payment tx-sender (as-contract tx-sender)))
      
      ;; Pay institution cut to lead researcher
      (if (> institution-cut u0)
          (as-contract (try! (stx-transfer? institution-cut tx-sender (get lead-researcher patent))))
          true)
      
      ;; Distribute remaining to all researchers based on their contributions
      (try! (distribute-to-all-researchers patent-id researcher-cut))
      
      (ok true))))

;; Helper function to distribute fees to all researchers
(define-private (distribute-to-all-researchers (patent-id uint) (total-amount uint))
  (begin
    ;; Validate inputs (patent-id already validated by caller, but add safety check)
    (asserts! (> patent-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (> total-amount u0) ERR-INVALID-PARAMETERS)
    
    (let ((patent (unwrap! (map-get? patents { patent-id: patent-id }) ERR-PATENT-NOT-REGISTERED))
          (lead-researcher (get lead-researcher patent))
          (lead-researcher-data (map-get? researchers { patent-id: patent-id, researcher: lead-researcher })))
      ;; For simplicity, this implementation adds fees to the lead researcher
      ;; In a full implementation, you'd need to iterate through all researchers
      (if (is-some lead-researcher-data)
          (let ((current-fees (default-to { accumulated-fees: u0 }
                                   (map-get? license-fees { patent-id: patent-id, researcher: lead-researcher }))))
            
            ;; Add to accumulated license fees for lead researcher
            (map-set license-fees
              { patent-id: patent-id, researcher: lead-researcher }
              { accumulated-fees: (+ (get accumulated-fees current-fees) total-amount) })
            
            (ok true))
          ERR-PATENT-NOT-REGISTERED))))

;; Distribute licensing fees to a specific researcher (called by researchers themselves)
(define-public (allocate-my-licensing-fees (patent-id uint) (total-fees uint))
  (begin
    ;; Validate inputs first
    (asserts! (< patent-id (var-get next-patent-id)) ERR-PATENT-NOT-REGISTERED)
    (asserts! (> patent-id u0) ERR-INVALID-PARAMETERS)
    (asserts! (> total-fees u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= total-fees u1000000000) ERR-INVALID-PARAMETERS)
    
    (let ((researcher-data (map-get? researchers { patent-id: patent-id, researcher: tx-sender })))
      (if (is-some researcher-data)
          (let ((researcher-contribution (get contribution-percentage (unwrap-panic researcher-data)))
                (researcher-fee (/ (* total-fees researcher-contribution) CONTRIBUTION-SCALE))
                (current-fees (default-to { accumulated-fees: u0 }
                                   (map-get? license-fees { patent-id: patent-id, researcher: tx-sender }))))
            
            ;; Validate calculated fee
            (asserts! (> researcher-fee u0) ERR-INVALID-PARAMETERS)
            
            ;; Add to accumulated license fees
            (map-set license-fees
              { patent-id: patent-id, researcher: tx-sender }
              { accumulated-fees: (+ (get accumulated-fees current-fees) researcher-fee) })
            
            (ok true))
          ERR-ACCESS-FORBIDDEN))))

;; Claim accumulated licensing fees
(define-public (claim-license-fees (patent-id uint))
  (begin
    ;; Validate patent-id first
    (asserts! (< patent-id (var-get next-patent-id)) ERR-PATENT-NOT-REGISTERED)
    (asserts! (> patent-id u0) ERR-INVALID-PARAMETERS)
    
    (let ((fees (unwrap! (map-get? license-fees { patent-id: patent-id, researcher: tx-sender }) ERR-NO-LICENSE-FEES))
          (amount (get accumulated-fees fees)))
      
      ;; Validate amount
      (asserts! (> amount u0) ERR-NO-LICENSE-FEES)
      
      ;; Reset accumulated fees
      (map-set license-fees
        { patent-id: patent-id, researcher: tx-sender }
        { accumulated-fees: u0 })
      
      ;; Transfer license fees to the researcher
      (as-contract (try! (stx-transfer? amount tx-sender tx-sender)))
      
      (ok amount))))

;; Toggle patent active status (lead researcher only)
(define-public (toggle-patent-status (patent-id uint))
  (begin
    ;; Validate patent-id first
    (asserts! (< patent-id (var-get next-patent-id)) ERR-PATENT-NOT-REGISTERED)
    (asserts! (> patent-id u0) ERR-INVALID-PARAMETERS)
    
    (let ((patent (unwrap! (map-get? patents { patent-id: patent-id }) ERR-PATENT-NOT-REGISTERED)))
      
      ;; Validate access
      (asserts! (is-eq tx-sender (get lead-researcher patent)) ERR-ACCESS-FORBIDDEN)
      
      ;; Toggle active status
      (map-set patents
        { patent-id: patent-id }
        (merge patent { active: (not (get active patent)) }))
      
      (ok true))))

;; Read-only functions
(define-read-only (get-patent (patent-id uint))
  (map-get? patents { patent-id: patent-id }))

(define-read-only (get-researcher (patent-id uint) (researcher principal))
  (map-get? researchers { patent-id: patent-id, researcher: researcher }))

(define-read-only (get-license-fees (patent-id uint) (researcher principal))
  (default-to { accumulated-fees: u0 }
              (map-get? license-fees { patent-id: patent-id, researcher: researcher })))

(define-read-only (get-next-patent-id)
  (var-get next-patent-id))

(define-read-only (patent-exists (patent-id uint))
  (is-some (map-get? patents { patent-id: patent-id })))

(define-read-only (get-total-patents)
  (- (var-get next-patent-id) u1))