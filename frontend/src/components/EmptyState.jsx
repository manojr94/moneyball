import PropTypes from 'prop-types'

export function EmptyState({ message }) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-slate-500">
      <p className="text-sm">{message}</p>
    </div>
  )
}

EmptyState.propTypes = { message: PropTypes.string.isRequired }
