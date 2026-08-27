export function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-slate-500">
      <p className="text-sm">{message}</p>
    </div>
  )
}
