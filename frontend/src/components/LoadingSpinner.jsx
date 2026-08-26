export function LoadingSpinner() {
  return (
    <div className="flex justify-center items-center py-12" role="status" aria-label="Loading">
      <div className="w-8 h-8 border-4 border-slate-200 border-t-indigo-600 rounded-full animate-spin" />
    </div>
  )
}
