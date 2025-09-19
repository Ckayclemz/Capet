# Research Patent Licensing Contract

A Clarity smart contract for managing research patent licensing and fee distribution among researchers and institutions.

## Overview

This contract enables researchers to:
- Register patents with licensing terms
- Add contributing researchers with specific contribution percentages
- File patent applications
- Process licensing transactions
- Distribute licensing fees automatically based on contributions
- Manage patent status and claims

## Features

- **Patent Registration**: Lead researchers can register patents with title, licensing fee, and institutional licensing rate
- **Contributor Management**: Add multiple researchers with specific contribution percentages
- **Fee Distribution**: Automatic distribution of licensing fees based on contribution percentages
- **Patent Filing**: Formal patent application filing with fee payment
- **Licensing Processing**: Handle licensing transactions from third parties
- **Fee Claims**: Researchers can claim their accumulated licensing fees

## Constants

- `MAX-LICENSING-RATE`: 450 (45% maximum institutional cut)
- `CONTRIBUTION-SCALE`: 1000 (100% = 1000 for percentage calculations)

## Data Structures

### Patents Map
```clarity
{
  patent-id: uint,
  patent-title: (string-utf8 128),
  lead-researcher: principal,
  licensing-fee: uint,
  licensing-rate: uint,
  filed: bool,
  active: bool
}
```

### Researchers Map
```clarity
{
  patent-id: uint,
  researcher: principal,
  contribution-percentage: uint,
  department: (string-ascii 32)
}
```

### License Fees Map
```clarity
{
  patent-id: uint,
  researcher: principal,
  accumulated-fees: uint
}
```

## Public Functions

### `register-patent`
Register a new research patent.

**Parameters:**
- `patent-title` (string-utf8 128): Title of the patent
- `licensing-fee` (uint): Filing fee required
- `licensing-rate` (uint): Institutional cut percentage (0-450, representing 0-45%)

**Returns:** Patent ID

**Requirements:**
- Licensing fee must be greater than 0
- Licensing rate cannot exceed 45%
- Patent title cannot be empty

### `add-researcher`
Add a contributing researcher to an existing patent.

**Parameters:**
- `patent-id` (uint): ID of the patent
- `researcher` (principal): Address of the researcher
- `contribution-percentage` (uint): Researcher's contribution (0-1000)
- `department` (string-ascii 32): Researcher's department

**Requirements:**
- Only lead researcher can add contributors
- Patent must not be filed yet
- Contribution percentage must be valid and not exceed lead researcher's remaining contribution

### `file-patent-application`
Submit patent application with required fee.

**Parameters:**
- `patent-id` (uint): ID of the patent to file

**Requirements:**
- Only lead researcher can file
- Patent must be active and not already filed
- Sufficient STX balance for filing fee

### `process-patent-licensing`
Process a licensing transaction and distribute fees.

**Parameters:**
- `patent-id` (uint): ID of the licensed patent
- `licensee` (principal): Address of the licensee
- `licensing-payment` (uint): Total licensing payment

**Requirements:**
- Patent must be active and filed
- Payment must be between 1 and 1,000,000,000 STX
- Sufficient STX balance for payment

### `allocate-my-licensing-fees`
Allocate licensing fees to a researcher based on their contribution.

**Parameters:**
- `patent-id` (uint): ID of the patent
- `total-fees` (uint): Total fees to allocate

**Requirements:**
- Researcher must be contributor to the patent
- Total fees must be valid amount

### `claim-license-fees`
Claim accumulated licensing fees.

**Parameters:**
- `patent-id` (uint): ID of the patent

**Returns:** Amount claimed

**Requirements:**
- Must have accumulated fees to claim

### `toggle-patent-status`
Toggle patent active/inactive status.

**Parameters:**
- `patent-id` (uint): ID of the patent

**Requirements:**
- Only lead researcher can toggle status

## Read-Only Functions

### `get-patent`
Retrieve patent information.

### `get-researcher`
Get researcher contribution details for a patent.

### `get-license-fees`
Check accumulated fees for a researcher on a patent.

### `get-next-patent-id`
Get the next available patent ID.

### `patent-exists`
Check if a patent exists.

### `get-total-patents`
Get total number of registered patents.

## Usage Examples

### 1. Register a New Patent
```clarity
(contract-call? .patent-contract register-patent 
  u"Novel AI Algorithm for Drug Discovery" 
  u1000000    ;; 1 STX filing fee
  u300)       ;; 30% institutional rate
```

### 2. Add a Contributing Researcher
```clarity
(contract-call? .patent-contract add-researcher 
  u1              ;; patent-id
  'ST1RESEARCHER  ;; researcher address
  u200            ;; 20% contribution
  "biochemistry") ;; department
```

### 3. File Patent Application
```clarity
(contract-call? .patent-contract file-patent-application u1)
```

### 4. Process Licensing Transaction
```clarity
(contract-call? .patent-contract process-patent-licensing 
  u1              ;; patent-id
  'ST1LICENSEE    ;; licensee address
  u5000000)       ;; 5 STX licensing payment
```

### 5. Claim Licensing Fees
```clarity
(contract-call? .patent-contract claim-license-fees u1)
```

## Error Codes

- `u100`: Access forbidden
- `u101`: Patent not registered
- `u102`: Invalid parameters
- `u103`: Already filed
- `u104`: Insufficient funding
- `u105`: No license fees available

## Fee Distribution Logic

1. **Institution Cut**: Calculated as `(licensing-payment * licensing-rate) / 1000`
2. **Researcher Pool**: Remaining amount after institution cut
3. **Individual Share**: Based on each researcher's contribution percentage

## Security Considerations

- Only lead researchers can modify patent details
- Patent filing requires actual STX payment
- Licensing fees are held in contract until claimed
- All financial operations include balance checks
- Input validation on all parameters

## Development Notes

- Built for Stacks blockchain using Clarity language
- Uses STX as the native currency for all transactions
- Contract owner is set to the deployer address
- All percentage calculations use basis points (1000 = 100%)

