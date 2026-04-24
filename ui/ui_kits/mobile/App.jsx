/* global React, Icon, Avatar, Card, ListTile, SummaryCard, SectionHeader, MoneyLabel,
   AppBar, BottomNav, Fab, FilledButton, TextButton, TextField, Chip, DropdownRow,
   IOSDevice, AndroidDevice */
const { useState } = React;

// ---------- SEED DATA (mirrors DashboardSnapshot shape) ----------
const seed = {
  overallLabel: "Overall, you are owed",
  overallAmountText: "₹1,250.00",
  overallPositive: true,
  friendItems: [
    { title: "Aarav Sharma", subtitle: "owes you", amountText: "₹450.00", positive: true, bg: "#CFE0FA", fg: "#0C2D63" },
    { title: "Priya Iyer",   subtitle: "you owe",  amountText: "₹120.00", positive: false, bg: "#F7D7D7", fg: "#5e1b1b" },
    { title: "Rohan Mehta",  subtitle: "owes you", amountText: "₹820.00", positive: true, bg: "#DCE7FF", fg: "#0c2d63" },
    { title: "Neha Kapoor",  subtitle: "settled",  amountText: "—",        positive: true, bg: "#E4E2E8", fg: "#45474A" },
  ],
  groupItems: [
    { title: "Trip to Goa",      subtitle: "4 people · last activity 2d", amountText: "you owe ₹340" },
    { title: "Flat 3B",          subtitle: "3 people · last activity 5h", amountText: "owes you ₹1,590" },
    { title: "Dinner club",      subtitle: "6 people · settled",          amountText: "settled" },
  ],
  familyHousehold: {
    name: "Rao Family",
    members: 4,
    monthBudget: "₹45,000",
    monthSpent: "₹28,340",
    monthRemaining: "₹16,660",
  },
  familyMembers: [
    { title: "Nisha (you)",   subtitle: "paid ₹12,400 this month", amountText: "₹12,400", positive: true,  bg: "#CFE0FA", fg: "#0C2D63" },
    { title: "Arjun",         subtitle: "paid ₹8,900 this month",  amountText: "₹8,900",  positive: true,  bg: "#DCE7FF", fg: "#0c2d63" },
    { title: "Maa",           subtitle: "paid ₹5,600 this month",  amountText: "₹5,600",  positive: true,  bg: "#F7D7D7", fg: "#5e1b1b" },
    { title: "Papa",          subtitle: "paid ₹1,440 this month",  amountText: "₹1,440",  positive: true,  bg: "#FDE6B8", fg: "#5c3e0a" },
  ],
  familyCategories: [
    { title: "Groceries",       subtitle: "14 expenses · this month", amountText: "₹8,720" },
    { title: "Utilities",       subtitle: "electricity, gas, water",   amountText: "₹4,280" },
    { title: "Rent & housing",  subtitle: "auto-split equally",        amountText: "₹12,000" },
    { title: "School & kids",   subtitle: "fees, supplies",            amountText: "₹3,340" },
  ],
  activityItems: [
    { title: "Aarav paid for Groceries",     subtitle: "You owe ₹120.00",    amountText: "₹120.00",  positive: false },
    { title: "You paid for Cab to airport",  subtitle: "Trip to Goa · split", amountText: "₹450.00", positive: true },
    { title: "Priya added Internet bill",    subtitle: "Flat 3B",             amountText: "₹80.00",  positive: false },
    { title: "You settled up with Rohan",    subtitle: "5 days ago",          amountText: "₹250.00", positive: true },
  ],
  // 7-day spend series — Mon..Sun in ₹ hundreds
  spendTrend: {
    labels: ["M", "T", "W", "T", "F", "S", "S"],
    values: [420, 180, 650, 320, 910, 1240, 540],
    total: "₹4,260",
    vsLast: "+12% vs last week",
    positive: false,
  },
  spendByCategory: [
    { label: "Groceries",  amount: "₹8,720",  pct: 31, color: "#3B7FE0" },
    { label: "Rent",       amount: "₹12,000", pct: 42, color: "#7AA2F7" },
    { label: "Utilities",  amount: "₹4,280",  pct: 15, color: "#CFE0FA" },
    { label: "Other",      amount: "₹3,340",  pct: 12, color: "#E4E2E8" },
  ],
  accountName: "Nisha Rao",
  accountEmail: "nisha.rao@example.com",
};

// ---------- PAGES ----------

function FriendsPage({ onAddFriend }) {
  return (
    <div style={pageStyle}>
      <SummaryCard title={seed.overallLabel} amount={seed.overallAmountText} positive={seed.overallPositive} />
      <div style={{ height: 16 }}/>
      <SectionHeader title="Friends" action="Add friend" onAction={onAddFriend} />
      {seed.friendItems.map((f) => (
        <ListTile key={f.title}
          leading={<Avatar bg={f.bg} fg={f.fg}>{Icon.person(false)}</Avatar>}
          title={f.title} subtitle={f.subtitle}
          trailing={f.amountText === "—"
            ? <div style={{ fontSize: 14, color: "#58646F" }}>settled</div>
            : <MoneyLabel amount={f.amountText} positive={f.positive} />} />
      ))}
    </div>
  );
}

function GroupsPage() {
  return (
    <div style={pageStyle}>
      <SummaryCard title={seed.overallLabel} amount={seed.overallAmountText} positive={seed.overallPositive} />
      <div style={{ height: 16 }}/>
      {seed.groupItems.map((g) => (
        <ListTile key={g.title}
          leading={<Avatar bg="#CFE0FA" fg="#0C2D63">{Icon.group(false)}</Avatar>}
          title={g.title} subtitle={g.subtitle}
          trailing={<div style={{ fontSize: 14, fontWeight: 500, color: "#45474A", fontFeatureSettings: '"tnum" 1' }}>{g.amountText}</div>} />
      ))}
    </div>
  );
}

function FamilyPage() {
  const h = seed.familyHousehold;
  return (
    <div style={pageStyle}>
      {/* Household budget card */}
      <Card>
        <div style={{ padding: 16 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 14 }}>
            <Avatar bg="#CFE0FA" fg="#0C2D63" size={44}>{Icon.family(true)}</Avatar>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E" }}>{h.name}</div>
              <div style={{ fontSize: 13, color: "#58646F", marginTop: 2 }}>{h.members} members · shared household</div>
            </div>
          </div>
          <div style={{ fontSize: 12, color: "#58646F", textTransform: "uppercase", letterSpacing: 0.4, marginBottom: 4 }}>This month</div>
          <div style={{ display: "flex", alignItems: "baseline", gap: 8, marginBottom: 12 }}>
            <div style={{ fontSize: 24, fontWeight: 700, color: "#1A1C1E", fontFeatureSettings: '"tnum" 1' }}>{h.monthSpent}</div>
            <div style={{ fontSize: 14, color: "#58646F" }}>of {h.monthBudget}</div>
          </div>
          {/* progress bar */}
          <div style={{ height: 8, borderRadius: 999, background: "#EEF0F3", overflow: "hidden" }}>
            <div style={{ height: "100%", width: "63%", background: "#3B7FE0" }}/>
          </div>
          <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8, fontSize: 12, color: "#58646F" }}>
            <span>63% spent</span>
            <span>{h.monthRemaining} left</span>
          </div>
        </div>
      </Card>
      <div style={{ height: 16 }}/>

      <SectionHeader title="Members" action="Invite" />
      {seed.familyMembers.map((m) => (
        <ListTile key={m.title}
          leading={<Avatar bg={m.bg} fg={m.fg}>{Icon.person(false)}</Avatar>}
          title={m.title} subtitle={m.subtitle}
          trailing={<div style={{ fontSize: 14, fontWeight: 500, color: "#45474A", fontFeatureSettings: '"tnum" 1' }}>{m.amountText}</div>} />
      ))}

      <div style={{ height: 16 }}/>
      <SectionHeader title="Categories" action="Manage" />
      {seed.familyCategories.map((c) => (
        <ListTile key={c.title}
          leading={<Avatar bg="#DCE7FF" fg="#0c2d63">{Icon.receipt}</Avatar>}
          title={c.title} subtitle={c.subtitle}
          trailing={<div style={{ fontSize: 14, fontWeight: 500, color: "#45474A", fontFeatureSettings: '"tnum" 1' }}>{c.amountText}</div>} />
      ))}
    </div>
  );
}

// Simple SVG line+area chart
function SpendChart({ labels, values, color = "#3B7FE0" }) {
  const W = 320, H = 120, P = 8;
  const max = Math.max(...values) * 1.15;
  const stepX = (W - P * 2) / (values.length - 1);
  const pts = values.map((v, i) => [P + i * stepX, H - P - (v / max) * (H - P * 2)]);
  const path = pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ");
  const area = `${path} L ${pts[pts.length - 1][0].toFixed(1)} ${H - P} L ${pts[0][0].toFixed(1)} ${H - P} Z`;
  const peakIdx = values.indexOf(Math.max(...values));
  return (
    <div style={{ position: "relative" }}>
      <svg viewBox={`0 0 ${W} ${H + 22}`} width="100%" style={{ display: "block" }}>
        <defs>
          <linearGradient id="spendFill" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity="0.22"/>
            <stop offset="100%" stopColor={color} stopOpacity="0"/>
          </linearGradient>
        </defs>
        {/* gridlines */}
        {[0.25, 0.5, 0.75].map((f) => (
          <line key={f} x1={P} x2={W - P} y1={P + (H - P * 2) * f} y2={P + (H - P * 2) * f}
                stroke="#EEF0F3" strokeWidth="1"/>
        ))}
        <path d={area} fill="url(#spendFill)"/>
        <path d={path} fill="none" stroke={color} strokeWidth="2" strokeLinejoin="round" strokeLinecap="round"/>
        {pts.map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r={i === peakIdx ? 4 : 2.5}
                  fill={i === peakIdx ? color : "#fff"}
                  stroke={color} strokeWidth="1.6"/>
        ))}
        {labels.map((l, i) => (
          <text key={i} x={pts[i][0]} y={H + 14} textAnchor="middle"
                fontSize="11" fill="#58646F" fontFamily="inherit">{l}</text>
        ))}
      </svg>
    </div>
  );
}

function CategoryBar({ items }) {
  return (
    <div>
      {/* stacked segmented bar */}
      <div style={{ display: "flex", height: 10, borderRadius: 999, overflow: "hidden", background: "#EEF0F3" }}>
        {items.map((c) => (
          <div key={c.label} style={{ width: c.pct + "%", background: c.color }}/>
        ))}
      </div>
      <div style={{ marginTop: 14, display: "grid", gap: 10 }}>
        {items.map((c) => (
          <div key={c.label} style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div style={{ width: 10, height: 10, borderRadius: 3, background: c.color, flexShrink: 0 }}/>
            <div style={{ flex: 1, fontSize: 14, color: "#1A1C1E" }}>{c.label}</div>
            <div style={{ fontSize: 13, color: "#58646F", fontFeatureSettings: '"tnum" 1' }}>{c.pct}%</div>
            <div style={{ width: 70, textAlign: "right", fontSize: 14, fontWeight: 500, color: "#1A1C1E", fontFeatureSettings: '"tnum" 1' }}>{c.amount}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function ActivityPage() {
  const [range, setRange] = useState("Week");
  const ranges = ["Week", "Month", "Year"];
  const t = seed.spendTrend;
  return (
    <div style={pageStyle}>
      {/* Chart card */}
      <Card>
        <div style={{ padding: 16 }}>
          <div style={{ display: "flex", alignItems: "flex-start", justifyContent: "space-between", marginBottom: 10 }}>
            <div>
              <div style={{ fontSize: 12, color: "#58646F", textTransform: "uppercase", letterSpacing: 0.4 }}>You spent</div>
              <div style={{ fontSize: 24, fontWeight: 700, color: "#1A1C1E", fontFeatureSettings: '"tnum" 1', marginTop: 2 }}>{t.total}</div>
              <div style={{ fontSize: 12, color: t.positive ? "#1B8C67" : "#BA1A1A", marginTop: 2 }}>{t.vsLast}</div>
            </div>
            <div style={{ display: "inline-flex", border: "1px solid #D9DBE0", borderRadius: 999, overflow: "hidden", background: "#fff" }}>
              {ranges.map((r, i) => (
                <button key={r} onClick={() => setRange(r)} style={{
                  border: "none", borderLeft: i ? "1px solid #D9DBE0" : "none",
                  background: range === r ? "rgba(59, 127, 224, 0.16)" : "transparent",
                  padding: "6px 12px", fontSize: 12, fontFamily: "inherit",
                  color: range === r ? "#2C68BF" : "#45474A", fontWeight: 500, cursor: "pointer",
                }}>{r}</button>
              ))}
            </div>
          </div>
          <SpendChart labels={t.labels} values={t.values}/>
        </div>
      </Card>
      <div style={{ height: 12 }}/>

      {/* Category breakdown */}
      <Card>
        <div style={{ padding: 16 }}>
          <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E", marginBottom: 12 }}>By category</div>
          <CategoryBar items={seed.spendByCategory}/>
        </div>
      </Card>
      <div style={{ height: 20 }}/>

      {/* History */}
      <SectionHeader title="History" action="See all" />
      {seed.activityItems.map((a, i) => (
        <ListTile key={i}
          leading={<div style={{ width: 28, color: "#58646F" }}>{Icon.receipt}</div>}
          title={a.title} subtitle={a.subtitle}
          trailing={<MoneyLabel amount={a.amountText} positive={a.positive}/>} />
      ))}
    </div>
  );
}

function AccountPage({ onNav }) {
  return (
    <div style={pageStyle}>
      <Card>
        <div style={{ padding: "12px 16px", display: "flex", alignItems: "center", gap: 14 }}>
          <Avatar bg="#3B7FE0" fg="#fff" size={44}>{Icon.person(true)}</Avatar>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E" }}>{seed.accountName}</div>
            <div style={{ fontSize: 13, color: "#58646F", marginTop: 2 }}>{seed.accountEmail}</div>
          </div>
          <TextButton>Edit</TextButton>
        </div>
      </Card>
      <div style={{ height: 8 }}/>
      {["Notifications", "Security", "Theme", "Help and feedback", "Logout"].map((label) => (
        <Card key={label} onClick={() => label === "Theme" && onNav?.("theme")}>
          <div style={{ padding: "14px 16px", display: "flex", alignItems: "center" }}>
            <div style={{ flex: 1, fontSize: 15, color: "#1A1C1E" }}>{label}</div>
            <div style={{ width: 18, height: 18, color: "#58646F" }}>{Icon.chevron}</div>
          </div>
        </Card>
      ))}
    </div>
  );
}

function AddExpensePage({ onClose }) {
  const [desc, setDesc] = useState("");
  const [amt, setAmt] = useState("");
  return (
    <div style={{ ...pageStyle, paddingTop: 12 }}>
      <Card>
        <div style={{ padding: 16 }}>
          <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E", marginBottom: 10 }}>With you and</div>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 8, marginBottom: 16 }}>
            <Chip selected>All of this group</Chip>
          </div>
          <TextField label="Description" value={desc} onChange={setDesc} />
          <TextField label="Amount" value={amt} onChange={setAmt} prefix="INR" type="text" />
          <div style={{ display: "flex", gap: 12 }}>
            <div style={{ flex: 1 }}><DropdownRow label="Paid by" value="You"/></div>
            <div style={{ flex: 1 }}><DropdownRow label="Split"   value="Equally"/></div>
          </div>
        </div>
      </Card>
      <div style={{ height: 16 }}/>
      <FilledButton onClick={onClose} icon={Icon.check}>Save expense</FilledButton>
    </div>
  );
}

function ThemePage({ onBack }) {
  const [variant, setVariant] = useState("Light");
  const variants = ["Light", "Dark", "High Contrast", "Custom"];
  const swatches = [
    { label: "Tokyo Night", color: "#7AA2F7" },
    { label: "Storm", color: "#3B7FE0" },
    { label: "Mint", color: "#3FBF9B" },
    { label: "Coral", color: "#FF6B6B" },
    { label: "Amber", color: "#E8A317" },
    { label: "Violet", color: "#9D7CFF" },
  ];
  return (
    <div style={pageStyle}>
      <DropdownRow label="Theme family" value="Tokyo Night" />
      <div style={{ height: 16 }}/>
      <div style={{ display: "inline-flex", border: "1px solid #D9DBE0", borderRadius: 999, overflow: "hidden", background: "#fff", width: "100%" }}>
        {variants.map((v, i) => (
          <button key={v} onClick={() => setVariant(v)} style={{
            flex: 1, border: "none", borderLeft: i ? "1px solid #D9DBE0" : "none",
            background: variant === v ? "rgba(59, 127, 224, 0.16)" : "none",
            padding: "9px 8px", fontSize: 12, fontFamily: "inherit",
            color: variant === v ? "#2C68BF" : "#45474A", fontWeight: 500, cursor: "pointer",
          }}>{v}</button>
        ))}
      </div>
      <div style={{ height: 20 }}/>
      <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E", marginBottom: 10 }}>Live preview</div>
      <Card>
        <div style={{ padding: 14 }}>
          <div style={{ fontSize: 16, fontWeight: 500, marginBottom: 10 }}>tokyo night · {variant.toLowerCase()}</div>
          <div style={{ display: "flex", gap: 10 }}>
            {[{ label: "Primary", color: "#3B7FE0" }, { label: "Secondary", color: "#4A635A" }, { label: "Surface", color: "#FDFCFD" }].map((s) => (
              <div key={s.label} style={{ flex: 1 }}>
                <div style={{ height: 36, borderRadius: 8, background: s.color, border: "1px solid rgba(0,0,0,0.08)" }}/>
                <div style={{ fontSize: 12, color: "#58646F", textAlign: "center", marginTop: 4 }}>{s.label}</div>
              </div>
            ))}
          </div>
        </div>
      </Card>
      {variant === "Custom" && (
        <>
          <div style={{ height: 20 }}/>
          <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E", marginBottom: 10 }}>Custom accent</div>
          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            {swatches.map((s) => (
              <div key={s.label} style={{ width: 34, height: 34, borderRadius: 999, background: s.color, cursor: "pointer" }}/>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

const pageStyle = { padding: 16, background: "#F7F8F9", minHeight: "100%" };

// ---------- APP SHELL ----------
function MobileApp({ platform = "android" }) {
  const [tab, setTab] = useState(0);
  const [modal, setModal] = useState(null); // 'add' | 'theme' | null
  const tabs = ["Friends", "Family", "Groups", "Activity", "Account"];

  const page = modal === "add"   ? <AddExpensePage onClose={() => setModal(null)} />
             : modal === "theme" ? <ThemePage onBack={() => setModal(null)} />
             : tab === 0 ? <FriendsPage onAddFriend={() => {}} />
             : tab === 1 ? <FamilyPage />
             : tab === 2 ? <GroupsPage />
             : tab === 3 ? <ActivityPage />
             : <AccountPage onNav={setModal} />;

  const pageTitle = modal === "add" ? "Add an expense"
                   : modal === "theme" ? "Theme settings"
                   : tabs[tab];

  const showFab = !modal && tab < 4;

  const content = (
    <div data-screen-label={`${platform} - ${pageTitle}`} style={{
      width: "100%", height: "100%", background: "#F7F8F9",
      display: "flex", flexDirection: "column", position: "relative",
    }}>
      <AppBar
        title={pageTitle}
        leading={modal ? (
          <button onClick={() => setModal(null)} style={{
            background: "none", border: "none", padding: 8, cursor: "pointer", color: "#1A1C1E",
          }}><div style={{ width: 22, height: 22 }}>{Icon.back}</div></button>
        ) : null}
        actions={modal === "theme" ? <TextButton>Reset</TextButton> : null}
      />
      <div style={{ flex: 1, overflowY: "auto" }}>{page}</div>
      {showFab && <Fab onClick={() => setModal("add")} />}
      {!modal && <BottomNav index={tab} onChange={setTab} />}
    </div>
  );

  if (platform === "ios") {
    return (
      <IOSDevice width={390} height={800}>
        <div style={{ paddingTop: 54, height: "100%", boxSizing: "border-box" }}>
          {content}
        </div>
      </IOSDevice>
    );
  }
  return <AndroidDevice width={390} height={800}>{content}</AndroidDevice>;
}

Object.assign(window, { MobileApp, FriendsPage, FamilyPage, GroupsPage, ActivityPage, AccountPage, AddExpensePage, ThemePage, seed });
