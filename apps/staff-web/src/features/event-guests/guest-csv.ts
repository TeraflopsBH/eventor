export function formatGuestCsv(rows: readonly (readonly (string | number | null)[])[]): string {
  return rows.map((row) => row.map((cell) => {
    const text = String(cell ?? "");
    // Guard spreadsheet formulas (including whitespace and full-width prefixes) inside a quoted field.
    if (/^[\t\r\n]|^\s*[=+@＝＋－＠-]/u.test(text)) return `"\t${text.replaceAll('"', '""')}"`;
    return /[",;\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
  }).join(",")).join("\r\n") + "\r\n";
}

export function downloadGuestCsv(filename: string, csv: string): void {
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
