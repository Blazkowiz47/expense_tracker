package group

import "time"

func computeDisplayData(memberUIDs []string, expenses []GroupExpense) *GroupDisplayData {
	balances := make(map[string]GroupMemberBalance, len(memberUIDs))
	for _, uid := range memberUIDs {
		balances[uid] = GroupMemberBalance{}
	}

	attachmentCounts := make(map[string]int, len(expenses))
	totalSpend := 0.0
	totalAttachments := 0
	for _, expense := range expenses {
		totalSpend += expense.Amount

		count := len(expense.Attachments)
		attachmentCounts[expense.ID] = count
		totalAttachments += count

		payer := expense.PaidBy
		if payer == "" {
			payer = expense.CreatedBy
		}
		participants := expense.SplitWith
		if len(participants) == 0 {
			participants = memberUIDs
		}
		if len(participants) == 0 {
			continue
		}
		share := expense.Amount / float64(len(participants))
		for _, participant := range participants {
			entry := balances[participant]
			if participant != payer {
				entry.Owes += share
				entry.Net -= share
			}
			balances[participant] = entry
		}

		if payer != "" {
			payerEntry := balances[payer]
			payerEntry.Owed += expense.Amount - shareIfIncludesPayer(payer, participants, share)
			payerEntry.Net += expense.Amount - shareIfIncludesPayer(payer, participants, share)
			balances[payer] = payerEntry
		}
	}

	return &GroupDisplayData{
		ExpenseCount:     len(expenses),
		TotalSpend:       totalSpend,
		TotalAttachments: totalAttachments,
		AttachmentCounts: attachmentCounts,
		MemberBalances:   balances,
		UpdatedAt:        time.Now().UTC(),
	}
}

func shareIfIncludesPayer(payer string, participants []string, share float64) float64 {
	for _, participant := range participants {
		if participant == payer {
			return share
		}
	}
	return 0
}
