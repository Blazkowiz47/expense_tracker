/* global React */
const { useState } = React;

// Inline SVG icon set — Material-style outlined/filled pairs to mirror the
// Flutter source's Icons.person_outline / Icons.person pattern.
const Icon = {
  person: (f) => f
    ? <svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6v1H4v-1z"/></svg>
    : <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4 4-6 8-6s8 2 8 6"/></svg>,
  group: (f) => f
    ? <svg viewBox="0 0 24 24" fill="currentColor"><circle cx="9" cy="8" r="3.5"/><circle cx="17" cy="9" r="2.8"/><path d="M2 20c0-3 3-5 7-5s7 2 7 5v1H2v-1z"/><path d="M17 14c2.5 0 5 1.5 5 4v1h-5v-2c0-1.2-.4-2.2-1-3h1z"/></svg>
    : <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="9" cy="8" r="3.5"/><circle cx="17" cy="9" r="2.8"/><path d="M2 20c0-3 3-5 7-5s7 2 7 5"/><path d="M17 14c2.5 0 5 1.5 5 4"/></svg>,
  list: (f) => f
    ? <svg viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="4" width="18" height="16" rx="2"/><path stroke="#fff" strokeWidth="1.8" d="M7 9h10M7 13h10M7 17h6"/></svg>
    : <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 9h10M7 13h10M7 17h6"/></svg>,
  account: (f) => f
    ? <svg viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="10" r="3.2" fill="#fff"/><path fill="#fff" d="M6 18.5c1.5-2.5 3.5-3.5 6-3.5s4.5 1 6 3.5A9.96 9.96 0 0 1 12 22a9.96 9.96 0 0 1-6-3.5z"/></svg>
    : <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="10" r="3"/><path d="M6 19c1.5-2.5 3.5-3.5 6-3.5s4.5 1 6 3.5"/></svg>,
  family: (f) => f
    ? <svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3 3 10v11h6v-6h6v6h6V10z"/><path fill="#fff" d="M12 12.2l-.9-.85c-1-.95-1.9-1.8-1.9-2.85 0-.85.65-1.5 1.5-1.5.48 0 .94.22 1.3.58.36-.36.82-.58 1.3-.58.85 0 1.5.65 1.5 1.5 0 1.05-.9 1.9-1.9 2.85l-.9.85z"/></svg>
    : <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M3 10l9-7 9 7v11h-6v-6H9v6H3z"/><path d="M12 13.2l-.9-.85C10.1 11.4 9.2 10.55 9.2 9.5c0-.85.65-1.5 1.5-1.5.48 0 .94.22 1.3.58.36-.36.82-.58 1.3-.58.85 0 1.5.65 1.5 1.5 0 1.05-.9 1.9-1.9 2.85z"/></svg>,
  receipt: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7"><path d="M6 2h12v20l-3-2-3 2-3-2-3 2V2z"/><path d="M9 8h6M9 12h6M9 16h4"/></svg>,
  plus: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4"><path d="M12 5v14M5 12h14"/></svg>,
  chevron: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18l6-6-6-6"/></svg>,
  back: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M15 18l-6-6 6-6"/></svg>,
  check: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M5 12l5 5L20 7"/></svg>,
  close: <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M6 6l12 12M18 6L6 18"/></svg>,
};

// Avatar — solid-background CircleAvatar analog
function Avatar({ children, bg = "#E4E2E8", fg = "#45474A", size = 40 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: 999, background: bg, color: fg,
      display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0,
    }}>
      <div style={{ width: size * 0.55, height: size * 0.55 }}>{children}</div>
    </div>
  );
}

// Card — elevation 0, radius 14, hairline border (mirrors app_theme.dart)
function Card({ children, style, onClick }) {
  return (
    <div onClick={onClick} style={{
      background: "#fff", borderRadius: 14, border: "1px solid #EEF0F3",
      marginBottom: 8, cursor: onClick ? "pointer" : "default", ...style,
    }}>{children}</div>
  );
}

// ListTile — leading / title+subtitle / trailing
function ListTile({ leading, title, subtitle, trailing, onClick }) {
  return (
    <Card onClick={onClick}>
      <div style={{ padding: "12px 16px", display: "flex", alignItems: "center", gap: 14 }}>
        {leading}
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E", lineHeight: 1.2, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{title}</div>
          {subtitle && <div style={{ fontSize: 13, color: "#58646F", marginTop: 2, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{subtitle}</div>}
        </div>
        {trailing}
      </div>
    </Card>
  );
}

// Summary card — used on Friends & Groups
function SummaryCard({ title, amount, positive = true }) {
  return (
    <Card>
      <div style={{ padding: 16 }}>
        <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E" }}>{title}</div>
        <div style={{
          fontSize: 24, fontWeight: 700, marginTop: 6,
          color: positive ? "#1B8C67" : "#BA1A1A",
          fontFeatureSettings: '"tnum" 1',
        }}>{amount}</div>
      </div>
    </Card>
  );
}

// Section header with action
function SectionHeader({ title, action, onAction }) {
  return (
    <div style={{ display: "flex", alignItems: "center", padding: "4px 4px 8px" }}>
      <div style={{ fontSize: 16, fontWeight: 500, color: "#1A1C1E", flex: 1 }}>{title}</div>
      {action && (
        <button onClick={onAction} style={{
          background: "none", border: "none", color: "#3B7FE0", fontSize: 14, fontWeight: 500,
          padding: "6px 8px", cursor: "pointer", fontFamily: "inherit",
        }}>{action}</button>
      )}
    </div>
  );
}

// Money label — trailing amount with semantic color
function MoneyLabel({ amount, positive }) {
  return (
    <div style={{ textAlign: "right", fontSize: 14, fontWeight: 500,
      color: positive ? "#1B8C67" : "#BA1A1A",
      fontFeatureSettings: '"tnum" 1', flexShrink: 0,
    }}>{amount}</div>
  );
}

// Top AppBar — Material
function AppBar({ title, leading, actions }) {
  return (
    <div style={{
      height: 56, display: "flex", alignItems: "center", padding: "0 8px",
      background: "#fff", borderBottom: "1px solid #EEF0F3",
    }}>
      {leading || <div style={{ width: 16 }}/>}
      <div style={{ fontSize: 20, fontWeight: 500, color: "#1A1C1E", flex: 1, marginLeft: leading ? 8 : 8 }}>{title}</div>
      {actions}
    </div>
  );
}

// Bottom NavigationBar — 5 destinations, capsule indicator
function BottomNav({ index, onChange }) {
  const items = [
    { label: "Friends", icon: Icon.person },
    { label: "Family", icon: Icon.family },
    { label: "Groups", icon: Icon.group },
    { label: "Activity", icon: Icon.list },
    { label: "Account", icon: Icon.account },
  ];
  return (
    <div style={{
      background: "#fff", padding: "8px 4px 14px",
      display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 2,
      borderTop: "1px solid #EEF0F3",
    }}>
      {items.map((it, i) => {
        const active = i === index;
        return (
          <button key={it.label} onClick={() => onChange(i)} style={{
            display: "flex", flexDirection: "column", alignItems: "center", gap: 4,
            padding: "4px 0 6px", background: "none", border: "none", cursor: "pointer",
            color: active ? "#1A1C1E" : "#58646F", fontFamily: "inherit",
            fontSize: 11, fontWeight: 500, position: "relative",
          }}>
            <div style={{
              width: 56, height: 30, borderRadius: 999,
              background: "transparent",
              display: "flex", alignItems: "center", justifyContent: "center",
            }}>
              <div style={{ width: 22, height: 22 }}>{it.icon(active)}</div>
            </div>
            {it.label}
            {active && (
              <div style={{
                position: "absolute", left: "50%", bottom: -2, transform: "translateX(-50%)",
                width: 44, height: 3, borderRadius: 2, background: "#1A1C1E",
              }}/>
            )}
          </button>
        );
      })}
    </div>
  );
}

// FAB — extended, with receipt icon + label
function Fab({ onClick, label = "Add expense", icon = Icon.receipt }) {
  return (
    <button onClick={onClick} style={{
      position: "absolute", right: 16, bottom: 96, zIndex: 5,
      background: "#3B7FE0", color: "#fff", border: "none",
      borderRadius: 16, padding: "14px 20px", fontSize: 14, fontWeight: 500,
      display: "inline-flex", alignItems: "center", gap: 8,
      boxShadow: "0 6px 16px rgba(0,0,0,0.18)", cursor: "pointer",
      fontFamily: "inherit",
    }}>
      <div style={{ width: 20, height: 20 }}>{icon}</div>{label}
    </button>
  );
}

// Filled button (Material FilledButton)
function FilledButton({ children, onClick, icon }) {
  return (
    <button onClick={onClick} style={{
      background: "#3B7FE0", color: "#fff", border: "none",
      borderRadius: 22, padding: "12px 20px", fontSize: 14, fontWeight: 500,
      display: "inline-flex", alignItems: "center", gap: 8, cursor: "pointer",
      fontFamily: "inherit", width: "100%", justifyContent: "center",
    }}>
      {icon && <div style={{ width: 18, height: 18 }}>{icon}</div>}
      {children}
    </button>
  );
}

// Text button
function TextButton({ children, onClick }) {
  return (
    <button onClick={onClick} style={{
      background: "none", border: "none", color: "#3B7FE0", fontSize: 14,
      fontWeight: 500, padding: "8px 12px", cursor: "pointer", fontFamily: "inherit",
    }}>{children}</button>
  );
}

// Text field — Material OutlineInputBorder style
function TextField({ label, value, onChange, prefix, type = "text" }) {
  const [focused, setFocused] = useState(false);
  const hasValue = value !== undefined && value !== "";
  const raise = focused || hasValue;
  return (
    <div style={{ position: "relative", marginBottom: 12 }}>
      <span style={{
        position: "absolute",
        left: prefix && !raise ? 40 : 12,
        top: raise ? -7 : 14,
        background: "#fff", padding: "0 4px",
        fontSize: raise ? 11 : 15,
        color: focused ? "#3B7FE0" : "#58646F",
        transition: "all .15s", pointerEvents: "none",
      }}>{label}</span>
      {prefix && <span style={{
        position: "absolute", left: 12, top: "50%", transform: "translateY(-50%)",
        fontSize: 15, color: "#58646F", fontWeight: 500,
      }}>{prefix}</span>}
      <input type={type} value={value} onChange={(e) => onChange?.(e.target.value)}
        onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
        style={{
          width: "100%", boxSizing: "border-box",
          border: `${focused ? 2 : 1}px solid ${focused ? "#3B7FE0" : "#D9DBE0"}`,
          borderRadius: 6,
          padding: `${focused ? 13 : 14}px ${focused ? 11 : 12}px ${focused ? 11 : 12}px ${prefix ? (focused ? 43 : 44) : (focused ? 11 : 12)}px`,
          fontSize: 15, fontFamily: "inherit", color: "#1A1C1E", background: "#fff", outline: "none",
        }} />
    </div>
  );
}

// Chip — Material-style filled chip
function Chip({ children, selected }) {
  return (
    <span style={{
      background: selected ? "#CFE0FA" : "#E4E2E8",
      border: `1px solid ${selected ? "#89B4EE" : "transparent"}`,
      borderRadius: 8, padding: "6px 12px", fontSize: 13,
      color: "#1A1C1E", display: "inline-flex", alignItems: "center", gap: 4,
    }}>{children}</span>
  );
}

// Dropdown (displays as a selector row — not fully functional)
function DropdownRow({ label, value }) {
  return (
    <div style={{
      border: "1px solid #D9DBE0", borderRadius: 6, padding: "10px 12px",
      display: "flex", alignItems: "center", gap: 8, background: "#fff",
      position: "relative",
    }}>
      <span style={{
        position: "absolute", top: -7, left: 10, background: "#fff",
        padding: "0 4px", fontSize: 11, color: "#58646F",
      }}>{label}</span>
      <span style={{ flex: 1, fontSize: 15, color: "#1A1C1E" }}>{value}</span>
      <div style={{ width: 18, height: 18, color: "#58646F", transform: "rotate(90deg)" }}>{Icon.chevron}</div>
    </div>
  );
}

// Export everything to window
Object.assign(window, {
  Icon, Avatar, Card, ListTile, SummaryCard, SectionHeader, MoneyLabel,
  AppBar, BottomNav, Fab, FilledButton, TextButton, TextField, Chip, DropdownRow,
});
