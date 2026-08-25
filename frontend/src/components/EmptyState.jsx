import PropTypes from 'prop-types'

export function EmptyState({ message }) {
  return (
    <div className="empty-state">
      <p>{message}</p>
    </div>
  )
}

EmptyState.propTypes = { message: PropTypes.string.isRequired }
